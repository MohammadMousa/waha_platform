import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/data/catalog/local_catalog.dart';
import 'package:waha_kiosk/data/catalog/offline_mode.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/sync/device_settings.dart';
import 'package:waha_kiosk/data/sync/feeds.dart';
import 'package:waha_kiosk/models/cart_item.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/api_exceptions.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

Map<String, dynamic> prod(int id, String en,
        {String ar = '', bool active = true, bool pub = true, int? cat, String price = '1.75', String withVat = '2.01'}) =>
    {
      'id': id, 'barcode': 'B$id', 'sku': null,
      'name': {'en': en, 'ar': ar.isEmpty ? en : ar}, 'description': null,
      'price': price, 'priceWithVat': withVat, 'active': active, 'public': pub,
      'categoryId': cat, 'imageResourceId': id * 10, 'updatedAt': '2026-11-06T10:00:00Z',
    };

void main() {
  late AppDatabase db;
  late LocalCatalog cat;

  Future<void> markDone(List<String> feeds) async {
    for (final f in feeds) {
      await db.into(db.syncState).insertOnConflictUpdate(
          SyncStateCompanion(feed: Value(f), fullPullDone: const Value(true)));
    }
  }

  Future<void> load({bool ready = true}) async {
    await upsertPage(db, 'products', [
      prod(1, 'Banana', cat: 7),
      prod(2, 'apple', ar: 'تفاح', cat: 7),
      prod(3, 'Hidden', pub: false),
      prod(4, 'Retired', active: false),
      prod(5, 'Cola', cat: 8),
    ]);
    await upsertPage(db, 'barcodes', [
      {'id': 1, 'productId': 1, 'barcode': 'B1', 'primary': true, 'updatedAt': 'x'},
      {'id': 2, 'productId': 1, 'barcode': 'ALT-1', 'primary': false, 'updatedAt': 'x'},
      {'id': 3, 'productId': 4, 'barcode': 'B4', 'primary': true, 'updatedAt': 'x'},
    ]);
    await upsertPage(db, 'categories', [
      {'id': 8, 'name': {'en': 'Drinks'}, 'key': 'd', 'public': true, 'active': true, 'sortOrder': 2, 'imageResourceId': null, 'updatedAt': 'x'},
      {'id': 7, 'name': {'en': 'Fruit'}, 'key': 'f', 'public': true, 'active': true, 'sortOrder': 1, 'imageResourceId': null, 'updatedAt': 'x'},
      {'id': 9, 'name': {'en': 'Off'}, 'key': 'o', 'public': true, 'active': false, 'sortOrder': 0, 'imageResourceId': null, 'updatedAt': 'x'},
    ]);
    await upsertPage(db, 'product-images', [
      {'id': 1, 'productId': 1, 'resourceId': 99, 'sortOrder': 2, 'updatedAt': 'x'},
      {'id': 2, 'productId': 1, 'resourceId': 98, 'sortOrder': 1, 'updatedAt': 'x'},
    ]);
    await saveDeviceConfig(db, {
      'deviceId': 3, 'deviceNo': 1, 'storeId': 5, 'organizationId': 1,
      'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
      'shortCode': null, 'lastReferenceSerial': null,
    });
    if (ready) await markDone(kRequiredFeeds);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cat = LocalCatalog(db);
  });
  tearDown(() => db.close());

  test('nothing is served until the first full pull is done', () async {
    await load(ready: false);
    expect(await cat.isReady(), false);
    await expectLater(cat.findByBarcode('B1'), throwsA(isA<OfflineNotReadyException>()));
    await expectLater(cat.browse(), throwsA(isA<OfflineNotReadyException>()));
    await markDone(['products', 'barcodes']);
    expect(await cat.isReady(), false); // payment methods still missing
    await markDone(['payment-methods']);
    expect(await cat.isReady(), true);
  });

  test('a scan finds the product by any of its barcodes and shows the VAT-inclusive price',
      () async {
    await load();
    final a = await cat.findByBarcode('B1');
    final b = await cat.findByBarcode('ALT-1');
    expect(a!.id, 1);
    expect(b!.id, 1);
    expect(a.price, 2.01);
    expect(await cat.findByBarcode('NOPE'), isNull);
    // Inactive products are returned; the caller decides (scan_disabled_products).
    expect((await cat.findByBarcode('B4'))!.active, false);
  });

  test('browse and search show only active public products, ordered by English name',
      () async {
    await load();
    final all = await cat.browse();
    expect([for (final p in all.products) p.name['en']], ['apple', 'Banana', 'Cola']);
    final fruit = await cat.browse(categoryId: 7);
    expect([for (final p in fruit.products) p.id], [2, 1]);
    final s = await cat.search('ban');
    expect([for (final p in s.products) p.id], [1]);
    expect((await cat.search('تفاح')).products.single.id, 2);
    final paged = await cat.browse(size: 2);
    expect(paged.products.length, 2);
    expect(paged.hasMore, true);
    expect((await cat.browse(page: 1, size: 2)).hasMore, false);
  });

  test('categories: active and public only, in sort order; detail has the gallery in order',
      () async {
    await load();
    expect([for (final c in await cat.categories()) c.id], [7, 8]);
    final d = await cat.productDetail(1);
    expect(d!.imageResourceIds, [98, 99]);
    expect(await cat.productDetail(404), isNull);
  });

  test('the local quote matches what the server answered for the same cart', () async {
    await load();
    // Server answer for 2 x product 11 (net 1.75): subtotal 3.50, tax 0.53, total 4.03, unitPrice 2.01, lineTotal 4.03.
    final q = await cat.quote([CartItem(productId: 1, name: const {'en': 'Banana'}, quantity: 2)],
        scanDisabledAllowed: false);
    expect(q.subtotal, 3.50);
    expect(q.tax, 0.53);
    expect(q.total, 4.03);
    expect(q.items.single.unitPrice, 2.01);
    expect(q.items.single.lineTotal, 4.03);
    expect(q.discountAmount, 0);
  });

  test('an inactive product is refused in the quote unless scan_disabled_products is on',
      () async {
    await load();
    final cart = [CartItem(productId: 4, name: const {'en': 'Retired'}, quantity: 1)];
    await expectLater(cat.quote(cart, scanDisabledAllowed: false),
        throwsA(isA<ProductNotSellableException>()));
    expect((await cat.quote(cart, scanDisabledAllowed: true)).total, 2.01);
  });

  test('offline payment methods follow the contract rules', () async {
    await load();
    Map<String, dynamic> pm(int id, String key, String provider,
            {bool active = true, bool offline = true, String modes = 'KIOSK,WEB', int sort = 0, String? url}) =>
        {'id': id, 'key': key, 'displayName': {'en': key}, 'provider': provider,
         'availableModes': modes, 'offlineCapable': offline, 'active': active,
         'sortOrder': sort, 'paymentUrl': url, 'updatedAt': 'x'};
    await upsertPage(db, 'payment-methods', [
      pm(1, 'terminal', 'TERMINAL', sort: 5),
      pm(2, 'online', 'REDIRECT', offline: false),
      pm(3, 'webonly', 'TERMINAL', modes: 'WEB'),
      pm(4, 'off', 'TERMINAL', active: false),
      pm(5, 'storeoff', 'TERMINAL'),
      pm(6, 'urlnone', 'PAYMENT_URL'),
      pm(7, 'sim', 'SIMULATED', sort: 9),
    ]);
    await upsertPage(db, 'store-payment-methods', [
      {'id': 1, 'paymentMethodId': 5, 'active': false, 'sortOrder': null, 'updatedAt': 'x'},
      {'id': 2, 'paymentMethodId': 7, 'active': true, 'sortOrder': 1, 'updatedAt': 'x'},
    ]);
    final keys = [for (final m in await cat.offlinePaymentMethods()) m.key];
    expect(keys, ['sim', 'terminal']); // sim's store sortOrder 1 beats terminal's 5
  });

  test('a payment method carries its icon resource id; none keeps the fixed icon', () async {
    await load();
    await upsertPage(db, 'payment-methods', [
      {'id': 1, 'key': 'terminal', 'displayName': {'en': 't'}, 'provider': 'TERMINAL',
       'availableModes': 'KIOSK', 'offlineCapable': true, 'active': true,
       'sortOrder': 1, 'iconResourceId': 42, 'updatedAt': 'x'},
      {'id': 2, 'key': 'sim', 'displayName': {'en': 's'}, 'provider': 'SIMULATED',
       'availableModes': 'KIOSK', 'offlineCapable': true, 'active': true,
       'sortOrder': 2, 'updatedAt': 'x'},
    ]);
    final byKey = {for (final m in await cat.offlinePaymentMethods()) m.key: m};
    expect(byKey['terminal']!.iconResourceId, 42);
    expect(byKey['sim']!.iconResourceId, isNull);
  });

  group('ApiClient uses the local data only when offline mode is on', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await LocalPrefs.init();
      await load();
      OfflineMode.catalog = cat;
    });
    tearDown(() => OfflineMode.catalog = null);

    test('on: scan, browse, quote come from the database; unknown and inactive are refused',
        () async {
      await LocalPrefs.setOfflineMode(true);
      final api = ApiClient(baseUrl: 'http://127.0.0.1:1'); // unreachable on purpose
      expect((await api.getProductByBarcode('B1', 5)).id, 1);
      await expectLater(api.getProductByBarcode('NOPE', 5), throwsA(isA<ProductNotFoundException>()));
      await expectLater(api.getProductByBarcode('B4', 5), throwsA(isA<ProductNotSellableException>()));
      await LocalPrefs.setScanDisabledProducts(true);
      expect((await api.getProductByBarcode('B4', 5)).id, 4);
      expect((await api.getProducts(storeId: 5)).products.length, 3);
      expect((await api.getCategories(storeId: 5)).length, 2);
      final q = await api.quote([CartItem(productId: 1, name: const {}, quantity: 1)]);
      expect(q.total, 2.01);
    });

    test('off: the app still goes to the server (unreachable here, so it fails)', () async {
      await LocalPrefs.setOfflineMode(false);
      final api = ApiClient(baseUrl: 'http://127.0.0.1:1');
      await expectLater(api.getProductByBarcode('B1', 5), throwsA(isA<NetworkException>()));
    });
  });
}
