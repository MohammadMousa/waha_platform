import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Saves what the server answered on a normal read into the same local tables
/// the pull fills, so `caching` mode can answer from them when the server
/// cannot be reached.
///
/// Rules that must not be broken (offline.md section 1 and 5d):
///  - Only a complete answer creates or replaces a product row. A product
///    answer is complete when it carries the price without VAT and its
///    updated-at time (what `?full=1` adds). An incomplete answer never
///    creates a row and never touches the prices of an existing one, so a
///    good row is never replaced by a poorer one.
///  - A row is not replaced by an older answer (compared by updated-at).
///  - Error answers are never saved (callers only pass 200 answers).
///  - Nothing here moves a pull's saved position; a pull, when it runs later,
///    still overwrites these rows (the pull wins).
///  - Failing to save never breaks the read that was already answered.
class ReadCache {
  final AppDatabase db;
  ReadCache(this.db);

  String? _s(Object? v) => v?.toString();
  int? _i(Object? v) => v == null ? null : (v as num).toInt();
  // Prices arrive as JSON numbers on normal reads (text in the pull feeds);
  // the tables keep text, with two decimals when the number has no more.
  String _dec(Object v) {
    if (v is num) {
      final c = v * 100;
      return (c == c.roundToDouble()) ? v.toStringAsFixed(2) : v.toString();
    }
    return v.toString();
  }

  String? _json(Object? v) => v == null ? null : jsonEncode(v);

  /// True when [m] has everything a local product row needs.
  static bool isCompleteProduct(Map<String, dynamic> m) =>
      m['priceExVat'] != null &&
      m['priceWithVat'] != null &&
      (m['updatedAt']?.toString().isNotEmpty ?? false);

  /// Products from a barcode lookup, a list, a search or a detail answer.
  /// [scannedBarcode] is the code the customer scanned, when it was a lookup.
  Future<void> saveProducts(List<Map<String, dynamic>> items,
      {String? scannedBarcode}) async {
    try {
      await db.transaction(() async {
        for (final m in items) {
          await _saveProduct(m, scannedBarcode: scannedBarcode);
        }
      });
    } catch (_) {/* the read was answered; saving is best effort */}
  }

  Future<void> _saveProduct(Map<String, dynamic> m,
      {String? scannedBarcode}) async {
    final id = _i(m['id']);
    if (id == null) return;
    final existing = await (db.select(db.localProducts)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();

    if (!isCompleteProduct(m)) {
      // Not enough to price the product locally. Only refresh what does not
      // depend on the missing fields, and only for a product we already hold.
      if (existing == null) return;
      await (db.update(db.localProducts)..where((t) => t.id.equals(id))).write(
        LocalProductsCompanion(
          nameJson: Value(_json(m['name']) ?? existing.nameJson),
          descriptionJson: Value(_json(m['description']) ?? existing.descriptionJson),
          active: Value((m['active'] as bool?) ?? existing.active),
          isPublic: Value((m['publicListed'] as bool?) ?? existing.isPublic),
          categoryId: Value(_i(m['categoryId']) ?? existing.categoryId),
          imageResourceId:
              Value(_i(m['imageResourceId']) ?? existing.imageResourceId),
        ),
      );
      return;
    }

    final updatedAt = _s(m['updatedAt'])!;
    // Never go back in time: an older answer does not replace a newer row.
    if (existing != null &&
        existing.updatedAt.isNotEmpty &&
        updatedAt.compareTo(existing.updatedAt) < 0) {
      return;
    }
    await db.into(db.localProducts).insertOnConflictUpdate(
          LocalProductsCompanion.insert(
            id: Value(id),
            barcode: Value(_s(m['barcode']) ?? existing?.barcode),
            sku: Value(_s(m['sku'])),
            nameJson: _json(m['name']) ?? '{}',
            descriptionJson: Value(_json(m['description'])),
            price: _dec(m['priceExVat']),
            priceWithVat: _dec(m['priceWithVat']),
            active: (m['active'] as bool?) ?? true,
            isPublic: (m['publicListed'] as bool?) ?? true,
            categoryId: Value(_i(m['categoryId'])),
            imageResourceId: Value(_i(m['imageResourceId'])),
            updatedAt: updatedAt,
          ),
        );

    // Every barcode of the product, primary first (the full answer).
    final list = m['barcodeList'];
    if (list is List && list.isNotEmpty) {
      final keep = <int>[];
      for (final b in list) {
        final bm = b as Map<String, dynamic>;
        final bid = _i(bm['id']);
        if (bid == null) continue;
        keep.add(bid);
        await db.into(db.localBarcodes).insertOnConflictUpdate(
              LocalBarcodesCompanion.insert(
                id: Value(bid),
                productId: id,
                barcode: _s(bm['barcode']) ?? '',
                isPrimary: (bm['isPrimary'] as bool?) ?? false,
                updatedAt: updatedAt,
              ),
            );
      }
      // A barcode taken off the product on the server is taken off here too.
      await (db.delete(db.localBarcodes)
            ..where((t) => t.productId.equals(id) & t.id.isNotIn(keep)))
          .go();
    }
  }

  /// The category list the server returned (active and public ones only).
  /// A category we hold that is no longer in the list is hidden here too.
  Future<void> saveCategories(List<Map<String, dynamic>> items) async {
    try {
      await db.transaction(() async {
        final ids = <int>[];
        for (final m in items) {
          final id = _i(m['id']);
          if (id == null) continue;
          ids.add(id);
          await db.into(db.localCategories).insertOnConflictUpdate(
                LocalCategoriesCompanion.insert(
                  id: Value(id),
                  nameJson: _json(m['name']) ?? '{}',
                  key: Value(_s(m['key'])),
                  isPublic: (m['publicVisible'] as bool?) ?? true,
                  active: (m['active'] as bool?) ?? true,
                  sortOrder: _i(m['sortOrder']) ?? 0,
                  imageResourceId: Value(_i(m['imageResourceId'])),
                  updatedAt: _s(m['updatedAt']) ?? '',
                ),
              );
        }
        await (db.update(db.localCategories)..where((t) => t.id.isNotIn(ids)))
            .write(const LocalCategoriesCompanion(active: Value(false)));
      });
    } catch (_) {}
  }

  /// The payment methods the server returned for [mode]. The list holds only
  /// methods that are on, valid for the mode and enabled for the store, so a
  /// good list replaces what we hold for that mode: a method that is no longer
  /// in it is switched off here.
  Future<void> savePaymentMethods(
      String mode, List<Map<String, dynamic>> items) async {
    try {
      await db.transaction(() async {
        final upper = mode.toUpperCase();
        final ids = <int>[];
        for (final m in items) {
          final id = _i(m['id']);
          if (id == null) continue;
          ids.add(id);
          await db.into(db.localPaymentMethods).insertOnConflictUpdate(
                LocalPaymentMethodsCompanion.insert(
                  id: Value(id),
                  key: _s(m['key']) ?? '',
                  displayNameJson: Value(_json(m['displayName'])),
                  provider: _s(m['provider']) ?? '',
                  availableModes: Value(_s(m['availableModes']) ?? upper),
                  offlineCapable: (m['offlineCapable'] as bool?) ?? false,
                  active: true,
                  sortOrder: _i(m['sortOrder']) ?? 0,
                  paymentUrl: Value(_s(m['paymentUrl'])),
                  iconResourceId: Value(_i(m['iconResourceId'])),
                  updatedAt: _s(m['updatedAt']) ?? '',
                ),
              );
          // The answer is already the store's list with its own order, so a
          // store row saved by an earlier pull must not hide it.
          await (db.update(db.localStorePaymentMethods)
                ..where((t) => t.paymentMethodId.equals(id)))
              .write(LocalStorePaymentMethodsCompanion(
                  active: const Value(true), sortOrder: Value(_i(m['sortOrder']))));
        }
        final held = await db.select(db.localPaymentMethods).get();
        for (final r in held) {
          if (ids.contains(r.id)) continue;
          if ((r.availableModes ?? '').toUpperCase().contains(upper)) {
            await (db.update(db.localPaymentMethods)
                  ..where((t) => t.id.equals(r.id)))
                .write(const LocalPaymentMethodsCompanion(active: Value(false)));
          }
        }
      });
    } catch (_) {}
  }
}
