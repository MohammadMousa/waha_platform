import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// The pull feeds, in the order they are pulled. `path` is the table name in
/// GET /api/sync/{path}.
const List<String> kSyncFeeds = [
  'products',
  'barcodes',
  'categories',
  'payment-methods',
  'store-payment-methods',
  'product-images',
];

/// Feeds the kiosk must have fully pulled once before it may take orders.
const List<String> kRequiredFeeds = ['products', 'barcodes', 'payment-methods'];

String? _s(Object? v) => v?.toString();
int? _i(Object? v) => v == null ? null : (v as num).toInt();
// Names arrive as JSON objects; keep them as compact JSON text.
String? _json(Object? v) => v == null ? null : jsonEncode(v);

const Map<String, String> _tableOf = {
  'products': 'local_products',
  'barcodes': 'local_barcodes',
  'categories': 'local_categories',
  'payment-methods': 'local_payment_methods',
  'store-payment-methods': 'local_store_payment_methods',
  'product-images': 'local_product_images',
};

/// Writes one page of items into its table with upsert. Runs inside the
/// caller's transaction, together with the cursor update.
///
/// Returns how many rows were NEW or CHANGED (a different updatedAt than the
/// row already held). The server sends rows again for the 10 seconds before
/// the saved position, and a whole group saved in the same second always sits
/// inside that window, so the number of rows RECEIVED is never 0 even when
/// nothing changed. This number is what is shown to the person.
Future<int> upsertPage(
    AppDatabase db, String feed, List<Map<String, dynamic>> items) async {
  final table = _tableOf[feed];
  if (table == null) throw ArgumentError('Unknown feed: $feed');
  var changed = 0;
  if (items.isNotEmpty) {
    final ids = [for (final m in items) _i(m['id'])!];
    final held = {
      for (final r in await db
          .customSelect(
              'SELECT id, updated_at FROM $table WHERE id IN (${List.filled(ids.length, '?').join(',')})',
              variables: [for (final id in ids) Variable<int>(id)])
          .get())
        r.read<int>('id'): r.read<String>('updated_at'),
    };
    for (final m in items) {
      final before = held[_i(m['id'])!];
      if (before == null || before != (_s(m['updatedAt']) ?? '')) changed++;
    }
  }
  await db.batch((b) {
    for (final m in items) {
      switch (feed) {
        case 'products':
          b.insert(
              db.localProducts,
              LocalProductsCompanion.insert(
                id: Value(_i(m['id'])!),
                barcode: Value(_s(m['barcode'])),
                sku: Value(_s(m['sku'])),
                nameJson: _json(m['name']) ?? '{}',
                descriptionJson: Value(_json(m['description'])),
                price: _s(m['price']) ?? '0',
                priceWithVat: _s(m['priceWithVat']) ?? _s(m['price']) ?? '0',
                active: (m['active'] as bool?) ?? true,
                isPublic: (m['public'] as bool?) ?? true,
                categoryId: Value(_i(m['categoryId'])),
                imageResourceId: Value(_i(m['imageResourceId'])),
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'barcodes':
          b.insert(
              db.localBarcodes,
              LocalBarcodesCompanion.insert(
                id: Value(_i(m['id'])!),
                productId: _i(m['productId'])!,
                barcode: _s(m['barcode']) ?? '',
                isPrimary: (m['primary'] as bool?) ?? false,
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'categories':
          b.insert(
              db.localCategories,
              LocalCategoriesCompanion.insert(
                id: Value(_i(m['id'])!),
                nameJson: _json(m['name']) ?? '{}',
                key: Value(_s(m['key'])),
                isPublic: (m['public'] as bool?) ?? true,
                active: (m['active'] as bool?) ?? true,
                sortOrder: _i(m['sortOrder']) ?? 0,
                imageResourceId: Value(_i(m['imageResourceId'])),
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'payment-methods':
          b.insert(
              db.localPaymentMethods,
              LocalPaymentMethodsCompanion.insert(
                id: Value(_i(m['id'])!),
                key: _s(m['key']) ?? '',
                displayNameJson: Value(_json(m['displayName'])),
                provider: _s(m['provider']) ?? '',
                availableModes: Value(_s(m['availableModes'])),
                offlineCapable: (m['offlineCapable'] as bool?) ?? false,
                active: (m['active'] as bool?) ?? true,
                sortOrder: _i(m['sortOrder']) ?? 0,
                paymentUrl: Value(_s(m['paymentUrl'])),
                iconResourceId: Value(_i(m['iconResourceId'])),
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'store-payment-methods':
          b.insert(
              db.localStorePaymentMethods,
              LocalStorePaymentMethodsCompanion.insert(
                id: Value(_i(m['id'])!),
                paymentMethodId: _i(m['paymentMethodId'])!,
                active: (m['active'] as bool?) ?? true,
                sortOrder: Value(_i(m['sortOrder'])),
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'product-images':
          b.insert(
              db.localProductImages,
              LocalProductImagesCompanion.insert(
                id: Value(_i(m['id'])!),
                productId: _i(m['productId'])!,
                resourceId: _i(m['resourceId'])!,
                sortOrder: _i(m['sortOrder']) ?? 0,
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        default:
          throw ArgumentError('Unknown feed: $feed');
      }
    }
  });
  return changed;
}
