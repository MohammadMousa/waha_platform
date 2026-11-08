import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/data/catalog/local_catalog.dart';
import 'package:waha_kiosk/data/catalog/offline_mode.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/sync/device_settings.dart';
import 'package:waha_kiosk/data/sync/feeds.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/api_exceptions.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

/// Caching mode: server first, saved copy only when the server cannot be
/// reached (no connection, timeout, 5xx). A 4xx is never replaced by the copy.
Map<String, dynamic> fullProduct(int id,
        {String updatedAt = '2026-11-08T10:00:00Z',
        double withVat = 2.01,
        double exVat = 1.75,
        String name = 'Banana'}) =>
    {
      'id': id, 'barcode': 'B$id', 'name': {'en': name}, 'description': null,
      'price': withVat, 'priceWithVat': withVat, 'priceExVat': exVat,
      'sku': 'S$id', 'updatedAt': updatedAt, 'active': true,
      'publicListed': true, 'categoryId': 7, 'imageResourceId': null,
      'barcodeList': [
        {'id': id * 10, 'barcode': 'B$id', 'isPrimary': true},
        {'id': id * 10 + 1, 'barcode': 'ALT-$id', 'isPrimary': false},
      ],
    };

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase db;
  late HttpServer server;
  late ApiClient api;
  var status = 200;
  Object? body;
  final seen = <Uri>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    await LocalPrefs.saveConfig({'offline_mode': 'caching'});
    db = AppDatabase(NativeDatabase.memory());
    OfflineMode.catalog = LocalCatalog(db);
    status = 200;
    body = null;
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      seen.add(req.uri);
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body))
        ..close();
    });
    api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
  });
  tearDown(() async {
    OfflineMode.catalog = null;
    await server.close(force: true);
    await db.close();
  });

  Future<void> serverDown() => server.close(force: true);

  test('a scan asks for the full answer, saves it, and works with the server down',
      () async {
    body = fullProduct(1);
    expect((await api.getProductByBarcode('B1', 5)).id, 1);
    expect(seen.single.queryParameters['full'], '1');
    // another barcode of the same product was saved too
    await serverDown();
    expect((await api.getProductByBarcode('ALT-1', 5)).id, 1);
    expect((await api.getProductByBarcode('B1', 5)).id, 1);
    final row = await db.select(db.localProducts).getSingle();
    expect(row.price, '1.75');
    expect(row.priceWithVat, '2.01');
    expect(row.sku, 'S1');
  });

  test('a 404 or other 4xx is the server\'s answer, never the saved copy',
      () async {
    body = fullProduct(1);
    await api.getProductByBarcode('B1', 5);
    status = 404;
    body = {'message': 'no'};
    await expectLater(api.getProductByBarcode('B1', 5),
        throwsA(isA<ProductNotFoundException>()));
    status = 409;
    await expectLater(api.getProductByBarcode('B1', 5),
        throwsA(isA<ProductNotSellableException>()));
    status = 422;
    await expectLater(
        api.getProductByBarcode('B1', 5), throwsA(isA<UnknownApiException>()));
  });

  test('a 5xx falls back to the saved copy', () async {
    body = fullProduct(1);
    await api.getProductByBarcode('B1', 5);
    status = 503;
    expect((await api.getProductByBarcode('B1', 5)).id, 1);
  });

  test('error answers are never saved', () async {
    status = 500;
    body = fullProduct(9);
    await expectLater(api.getProductByBarcode('B9', 5), throwsA(anything));
    expect(await db.select(db.localProducts).get(), isEmpty);
  });

  test('an incomplete answer never creates a row and never changes prices',
      () async {
    // not complete: no priceExVat / updatedAt (server not updated yet)
    final plain = {
      'id': 2, 'barcode': 'B2', 'name': {'en': 'Plain'}, 'price': 2.0,
      'priceWithVat': 2.0, 'active': true, 'publicListed': true,
    };
    body = plain;
    await api.getProductByBarcode('B2', 5);
    expect(await db.select(db.localProducts).get(), isEmpty);

    // a good row exists; a poorer answer may refresh the name, not the prices
    body = fullProduct(2, name: 'Good');
    await api.getProductByBarcode('B2', 5);
    body = {...plain, 'name': {'en': 'Renamed'}, 'priceWithVat': 99.0};
    await api.getProductByBarcode('B2', 5);
    final row = await db.select(db.localProducts).getSingle();
    expect(row.price, '1.75');
    expect(row.priceWithVat, '2.01');
    expect(row.nameJson, contains('Renamed'));
    expect(row.sku, 'S2');
  });

  test('an older answer does not replace a newer row; a newer one does',
      () async {
    body = fullProduct(3, updatedAt: '2026-11-08T12:00:00Z', withVat: 5.0);
    await api.getProductByBarcode('B3', 5);
    body = fullProduct(3, updatedAt: '2026-11-08T09:00:00Z', withVat: 1.0);
    await api.getProductByBarcode('B3', 5);
    expect((await db.select(db.localProducts).getSingle()).priceWithVat, '5.00');
    body = fullProduct(3, updatedAt: '2026-11-08T13:00:00Z', withVat: 6.0);
    await api.getProductByBarcode('B3', 5);
    expect((await db.select(db.localProducts).getSingle()).priceWithVat, '6.00');
  });

  test('a barcode taken off the product on the server is taken off here', () async {
    body = fullProduct(4);
    await api.getProductByBarcode('B4', 5);
    final p = fullProduct(4, updatedAt: '2026-11-08T11:00:00Z');
    p['barcodeList'] = [
      {'id': 40, 'barcode': 'B4', 'isPrimary': true},
    ];
    body = p;
    await api.getProductByBarcode('B4', 5);
    await serverDown();
    expect((await api.getProductByBarcode('B4', 5)).id, 4);
    await expectLater(api.getProductByBarcode('ALT-4', 5),
        throwsA(isA<ProductNotFoundException>()));
  });

  test('list and search are saved; browse works with the server down', () async {
    body = {
      'products': [fullProduct(5, name: 'Apple'), fullProduct(6, name: 'Pear')],
      'page': 0, 'size': 50, 'hasMore': false,
    };
    await api.getProducts(storeId: 5);
    expect(seen.last.queryParameters['full'], '1');
    await api.searchProducts(q: 'a', storeId: 5);
    expect(seen.last.queryParameters['full'], '1');
    await serverDown();
    final page = await api.getProducts(storeId: 5);
    expect(page.products.map((p) => p.id).toSet(), {5, 6});
    expect((await api.searchProducts(q: 'pear')).products.single.id, 6);
  });

  test('categories: saved, and one the server stops listing is hidden', () async {
    body = [
      {'id': 1, 'name': {'en': 'A'}, 'publicVisible': true, 'active': true, 'sortOrder': 2, 'key': 'a', 'updatedAt': 'x'},
      {'id': 2, 'name': {'en': 'B'}, 'publicVisible': true, 'active': true, 'sortOrder': 1, 'key': 'b', 'updatedAt': 'x'},
    ];
    expect((await api.getCategories(storeId: 5)).length, 2);
    body = [
      {'id': 2, 'name': {'en': 'B'}, 'publicVisible': true, 'active': true, 'sortOrder': 1, 'key': 'b', 'updatedAt': 'x'},
    ];
    await api.getCategories(storeId: 5);
    await serverDown();
    final c = await api.getCategories(storeId: 5);
    expect(c.map((e) => e.id), [2]);
  });

  test('payment methods: a good list replaces what we hold for that mode', () async {
    Map<String, dynamic> pm(int id, String key, int sort) => {
          'id': id, 'key': key, 'displayName': {'en': key}, 'provider': 'GEIDEA',
          'offlineCapable': true, 'sortOrder': sort, 'paymentUrl': null,
          'availableModes': 'KIOSK', 'active': true, 'updatedAt': 'x',
        };
    body = [pm(1, 'card', 2), pm(2, 'cash', 1)];
    await api.getPaymentMethods(mode: 'KIOSK', storeId: 5);
    body = [pm(1, 'card', 1)]; // cash was switched off for this store
    await api.getPaymentMethods(mode: 'KIOSK', storeId: 5);
    await serverDown();
    final list = await api.getPaymentMethods(mode: 'KIOSK', storeId: 5);
    expect(list.map((m) => m.key), ['card']);
    expect(list.single.sortOrder, 1);
  });

  test('off mode asks without the full flag and saves nothing', () async {
    await LocalPrefs.saveConfig({'offline_mode': 'off'});
    body = fullProduct(7);
    await api.getProductByBarcode('B7', 5);
    expect(seen.single.queryParameters.containsKey('full'), isFalse);
    expect(await db.select(db.localProducts).get(), isEmpty);
  });

  group('full mode: a product missing locally is asked for and saved', () {
    setUp(() async {
      await LocalPrefs.saveConfig({'offline_mode': 'full'});
      for (final f in kRequiredFeeds) {
        await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion(feed: Value(f), fullPullDone: const Value(true)));
      }
      await saveDeviceConfig(db, {
        'deviceId': 3, 'deviceNo': 1, 'storeId': 5, 'organizationId': 1,
        'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
        'shortCode': null, 'lastReferenceSerial': null,
      });
    });

    test('found on the server: returned, saved, and found with the server down',
        () async {
      body = fullProduct(20);
      expect((await api.getProductByBarcode('B20', 5)).id, 20);
      expect(seen.single.queryParameters['full'], '1');
      await serverDown();
      expect((await api.getProductByBarcode('ALT-20', 5)).id, 20);
      expect((await api.getProductDetail(20)).id, 20);
    });

    test('a product that is local never asks the server', () async {
      body = fullProduct(21);
      await api.getProductByBarcode('B21', 5);
      seen.clear();
      await api.getProductByBarcode('B21', 5);
      expect(seen, isEmpty);
    });

    test('the server\'s 404 / 409 / 4xx are passed on and nothing is saved',
        () async {
      status = 404;
      body = {'message': 'no'};
      await expectLater(api.getProductByBarcode('X', 5),
          throwsA(isA<ProductNotFoundException>()));
      status = 409;
      await expectLater(api.getProductByBarcode('X', 5),
          throwsA(isA<ProductNotSellableException>()));
      status = 422;
      await expectLater(
          api.getProductByBarcode('X', 5), throwsA(isA<UnknownApiException>()));
      expect(await db.select(db.localProducts).get(), isEmpty);
    });

    test('5xx or server down: plain "not found", nothing saved, and fast',
        () async {
      status = 503;
      await expectLater(api.getProductByBarcode('X', 5),
          throwsA(isA<ProductNotFoundException>()));
      await serverDown();
      final t = Stopwatch()..start();
      await expectLater(api.getProductByBarcode('X', 5),
          throwsA(isA<ProductNotFoundException>()));
      expect(t.elapsed, lessThan(const Duration(seconds: 4)));
      expect(await db.select(db.localProducts).get(), isEmpty);
    });

    test('an inactive product fetched this way is refused like a local one',
        () async {
      body = {...fullProduct(22), 'active': false};
      await expectLater(api.getProductByBarcode('B22', 5),
          throwsA(isA<ProductNotSellableException>()));
    });
  });
}
