import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/cart_item.dart';
import '../../models/category.dart';
import '../../models/payment_method.dart';
import '../../models/product.dart';
import '../../models/product_page.dart';
import '../../models/quote.dart';
import '../../services/api_exceptions.dart';
import '../../services/local_prefs.dart';
import 'offline_level.dart';
import '../db/app_database.dart';
import '../orders/decimal.dart';
import '../orders/local_order_service.dart';
import '../orders/pricing.dart';
import '../sync/device_settings.dart';
import '../sync/feeds.dart';

/// Reads products, categories, barcodes and prices from the local database
/// and returns the same model classes the online API returns, so the screens
/// do not need to know which one answered. Mirrors the server's rules:
/// browse/search show only active + public products ordered by English name;
/// a scan resolves through the barcode table.
class LocalCatalog {
  final AppDatabase db;
  LocalCatalog(this.db);

  /// True once products, barcodes and payment methods each finished one full
  /// pull and the device settings were fetched (offline.md section 2).
  Future<bool> isReady() async {
    final rows = await db.select(db.syncState).get();
    final done = {for (final r in rows) r.feed: r.fullPullDone};
    if (!kRequiredFeeds.every((f) => done[f] == true)) return false;
    return await readDeviceSettings(db) != null;
  }

  Future<void> requireReady() async {
    // `caching` has no first download: the copy is whatever earlier reads
    // saved, so there is nothing to wait for.
    if (LocalPrefs.offlineLevel == OfflineLevel.caching) return;
    if (!await isReady()) throw OfflineNotReadyException();
  }

  Map<String, dynamic>? _obj(String? text) {
    if (text == null) return null;
    try {
      final d = jsonDecode(text);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// The price the customer sees: with VAT when prices include VAT (what the
  /// online API sends as `price`), otherwise the net price.
  Product _toProduct(LocalProduct r, bool includeVat,
      {List<int> gallery = const []}) =>
      Product(
        id: r.id,
        barcode: r.barcode ?? '',
        name: _obj(r.nameJson) ?? {},
        description: _obj(r.descriptionJson),
        price: double.parse(includeVat ? r.priceWithVat : r.price),
        active: r.active,
        publicListed: r.isPublic,
        categoryId: r.categoryId,
        imageResourceId: r.imageResourceId,
        imageResourceIds: gallery,
      );

  // Device settings only exist after a full-mode sync; in caching mode the
  // saved server config says whether shown prices include VAT.
  Future<bool> _includeVat() async =>
      (await readDeviceSettings(db))?.pricesIncludeVat ??
      !LocalPrefs.pricesExcludeVat;

  /// A scan: through the barcode table, then the product's own barcode.
  /// Returns null when the code is unknown. Inactive products ARE returned;
  /// the caller applies the `scan_disabled_products` rule.
  Future<Product?> findByBarcode(String barcode) async {
    await requireReady();
    final bc = await (db.select(db.localBarcodes)
          ..where((t) => t.barcode.equals(barcode))
          ..limit(1))
        .getSingleOrNull();
    LocalProduct? row;
    if (bc != null) {
      row = await (db.select(db.localProducts)
            ..where((t) => t.id.equals(bc.productId)))
          .getSingleOrNull();
    }
    row ??= await (db.select(db.localProducts)
          ..where((t) => t.barcode.equals(barcode))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return _toProduct(row, await _includeVat());
  }

  Future<ProductPage> browse(
      {int? categoryId, int page = 0, int size = 50}) async {
    await requireReady();
    return _page(
      where: 'is_public = 1 AND active = 1'
          '${categoryId != null ? ' AND category_id = ?' : ''}',
      args: [if (categoryId != null) Variable<int>(categoryId)],
      page: page,
      size: size,
    );
  }

  /// Name search in English and Arabic. (Tags are not synced, so unlike the
  /// server this does not search them.)
  Future<ProductPage> search(String q, {int page = 0, int size = 50}) async {
    await requireReady();
    final like = '%${q.trim().toLowerCase()}%';
    return _page(
      where: 'is_public = 1 AND active = 1 AND '
          "(LOWER(json_extract(name_json, '\$.en')) LIKE ? "
          "OR LOWER(json_extract(name_json, '\$.ar')) LIKE ?)",
      args: [Variable<String>(like), Variable<String>(like)],
      page: page,
      size: size,
    );
  }

  Future<ProductPage> _page({
    required String where,
    required List<Variable> args,
    required int page,
    required int size,
  }) async {
    final includeVat = await _includeVat();
    final rows = await db
        .customSelect(
          'SELECT * FROM local_products WHERE $where '
          "ORDER BY LOWER(json_extract(name_json, '\$.en')), id LIMIT ? OFFSET ?",
          variables: [...args, Variable<int>(size + 1), Variable<int>(page * size)],
          readsFrom: {db.localProducts},
        )
        .map((r) => db.localProducts.map(r.data))
        .get();
    final hasMore = rows.length > size;
    final shown = hasMore ? rows.sublist(0, size) : rows;
    return ProductPage(
      products: [for (final r in shown) _toProduct(r, includeVat)],
      page: page,
      size: size,
      hasMore: hasMore,
    );
  }

  Future<List<Category>> categories() async {
    await requireReady();
    final rows = await (db.select(db.localCategories)
          ..where((t) => t.isPublic.equals(true) & t.active.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
        .get();
    return [
      for (final r in rows)
        Category(
          id: r.id,
          name: _obj(r.nameJson) ?? {},
          imageResourceId: r.imageResourceId,
        ),
    ];
  }

  Future<Product?> productDetail(int id) async {
    await requireReady();
    final r = await (db.select(db.localProducts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    final imgs = await (db.select(db.localProductImages)
          ..where((t) => t.productId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
        .get();
    return _toProduct(r, await _includeVat(),
        gallery: [for (final i in imgs) i.resourceId]);
  }

  /// Payment methods offered while offline (offline.md section 5b): method
  /// active, KIOSK in its modes, store row missing or active, offlineCapable,
  /// a PAYMENT_URL one needs a URL. Ordered by the store row's sortOrder,
  /// else the global one.
  Future<List<PaymentMethod>> offlinePaymentMethods() async {
    await requireReady();
    final methods = await db.select(db.localPaymentMethods).get();
    final storeRows = await db.select(db.localStorePaymentMethods).get();
    final byMethod = {for (final s in storeRows) s.paymentMethodId: s};
    final out = <(int, PaymentMethod)>[];
    for (final m in methods) {
      if (!m.active || !m.offlineCapable) continue;
      final modes = (m.availableModes ?? '').toUpperCase();
      if (!modes.contains('KIOSK')) continue;
      final store = byMethod[m.id];
      if (store != null && !store.active) continue;
      if (m.provider == 'PAYMENT_URL' && (m.paymentUrl ?? '').trim().isEmpty) {
        continue;
      }
      final sort = store?.sortOrder ?? m.sortOrder;
      out.add((
        sort,
        PaymentMethod(
          id: m.id,
          key: m.key,
          displayName: _obj(m.displayNameJson),
          provider: m.provider,
          offlineCapable: true,
          sortOrder: sort,
          paymentUrl: m.paymentUrl,
        )
      ));
    }
    out.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.id.compareTo(b.$2.id));
    return [for (final e in out) e.$2];
  }

  /// The cart as order lines: net price for the order, display price for the
  /// screens, and the product name. Refuses what the quote refuses.
  Future<List<NewOrderLine>> orderLines(List<CartItem> cart,
      {required bool scanDisabledAllowed}) async {
    await requireReady();
    final settings = (await readDeviceSettings(db))!;
    final ids = [for (final c in cart) c.productId];
    final rows = await (db.select(db.localProducts)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final r in rows) r.id: r};
    final out = <NewOrderLine>[];
    for (final c in cart) {
      final r = byId[c.productId];
      if (r == null) {
        throw ProductNotSellableException(409, 'Product ${c.productId} does not exist');
      }
      if (!r.active && !scanDisabledAllowed) {
        throw const ProductNotSellableException(409, 'Product is not currently sellable');
      }
      out.add(NewOrderLine(
        productId: c.productId,
        quantity: c.quantity,
        unitPrice: r.price,
        nameJson: r.nameJson,
        displayUnitPrice: settings.pricesIncludeVat ? r.priceWithVat : r.price,
      ));
    }
    return out;
  }

  /// A quote for the cart, priced locally (offline.md section 5): each line
  /// is net plus its own tax, no offers or coupons. Shape matches the
  /// server's quote: `unitPrice` is the display price, `lineTotal` is
  /// net + tax of the line.
  Future<Quote> quote(List<CartItem> cart, {required bool scanDisabledAllowed}) async {
    await requireReady();
    final settings = (await readDeviceSettings(db))!;
    final ids = [for (final c in cart) c.productId];
    final rows = await (db.select(db.localProducts)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final r in rows) r.id: r};
    for (final c in cart) {
      final r = byId[c.productId];
      if (r == null) {
        throw ProductNotSellableException(409, 'Product ${c.productId} does not exist');
      }
      if (!r.active && !scanDisabledAllowed) {
        throw const ProductNotSellableException(409, 'Product is not currently sellable');
      }
    }
    final priced = priceCart(
      [for (final c in cart) PricingInput(c.productId, c.quantity, byId[c.productId]!.price)],
      vatRate: settings.vatRate,
    );
    final lines = <QuoteLine>[];
    for (var i = 0; i < cart.length; i++) {
      final c = cart[i];
      final p = priced.lines[i];
      final r = byId[c.productId]!;
      lines.add(QuoteLine(
        productId: c.productId,
        name: c.name,
        quantity: c.quantity,
        unitPrice: double.parse(settings.pricesIncludeVat ? r.priceWithVat : r.price),
        lineTotal: double.parse((Dec.parse(p.net) + Dec.parse(p.tax)).toFixed(2)),
      ));
    }
    return Quote(
      subtotal: double.parse(priced.subtotal),
      tax: double.parse(priced.tax),
      total: double.parse(priced.total),
      items: lines,
    );
  }
}
