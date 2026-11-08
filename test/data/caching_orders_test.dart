import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/data/catalog/local_catalog.dart';
import 'package:waha_kiosk/data/catalog/offline_mode.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/orders/local_order_service.dart';
import 'package:waha_kiosk/data/sync/device_settings.dart';
import 'package:waha_kiosk/models/cart_item.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/api_exceptions.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

/// Caching mode, orders: server first; the local order only when the server
/// cannot be reached (no connection, timeout, 5xx); never on a 4xx; never for
/// a cart with a coupon.
Map<String, dynamic> product(int id) => {
      'id': id, 'barcode': 'B$id', 'name': {'en': 'Banana'}, 'description': null,
      'price': 2.01, 'priceWithVat': 2.01, 'priceExVat': 1.75, 'sku': null,
      'updatedAt': '2026-11-08T10:00:00Z', 'active': true, 'publicListed': true,
      'categoryId': null, 'imageResourceId': null,
      'barcodeList': [
        {'id': id * 10, 'barcode': 'B$id', 'isPrimary': true}
      ],
    };

Map<String, dynamic> serverOrder(String id) => {
      'orderId': id, 'status': 'CREATED', 'subtotal': 1.75, 'tax': 0.26,
      'total': 2.01, 'items': [], 'displayId': 501,
      'invoiceUrl': 'http://srv/api/invoices/$id',
    };

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase db;
  late HttpServer server;
  late ApiClient api;
  var status = 200;
  Object? body;
  final seen = <String>[];
  final cart = [CartItem(productId: 1, name: const {'en': 'Banana'}, quantity: 2)];
  const id = '0193aaaa-0000-7000-8000-000000000001';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      seen.add('${req.method} ${req.uri.path}');
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body))
        ..close();
    });
    api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    await LocalPrefs.saveConfig({'offline_mode': 'caching'});
    db = AppDatabase(NativeDatabase.memory());
    OfflineMode.catalog = LocalCatalog(db);
    OfflineMode.orders = LocalOrderService(db);
    await saveDeviceConfig(db, {
      'deviceId': 3, 'deviceNo': 1, 'storeId': 5, 'organizationId': 1,
      'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
      'shortCode': 'WH', 'lastReferenceSerial': null,
      'invoiceBaseUrl': 'http://srv',
    });
    status = 200;
    body = product(1);
    seen.clear();
    await start();
    await api.getProductByBarcode('B1', 5); // saves the product for later
    seen.clear();
  });
  tearDown(() async {
    OfflineMode.catalog = null;
    OfflineMode.orders = null;
    await server.close(force: true);
    await db.close();
  });

  Future<int> localOrders() async => (await db.select(db.localOrders).get()).length;

  test('server up: the server makes the order, nothing is made locally', () async {
    body = serverOrder(id);
    final o = await api.createOrder(id, cart, storeId: 5);
    expect(o.displayId, 501);
    expect(o.invoiceUrl, 'http://srv/api/invoices/$id'); // plain link
    expect(seen, ['POST /api/orders']);
    expect(await localOrders(), 0);
  });

  test('server error 5xx: the order is made locally with the same id', () async {
    status = 503;
    final o = await api.createOrder(id, cart, storeId: 5);
    expect(o.orderId, id);
    expect(o.total, 4.03);
    expect(o.invoiceUrl, 'http://srv/api/invoices/$id?offline=1');
    expect(o.orderReference, startsWith('WH-'));
    expect(await localOrders(), 1);
  });

  test('server down: the order is made locally', () async {
    await server.close(force: true);
    final o = await api.createOrder(id, cart, storeId: 5);
    expect(o.orderId, id);
    expect(await localOrders(), 1);
    // asking again with the same id changes nothing
    await api.createOrder(id, cart, storeId: 5);
    expect(await localOrders(), 1);
  });

  test('4xx is the server\'s answer: shown as is, no local order', () async {
    status = 409;
    body = {'message': 'not sellable'};
    await expectLater(api.createOrder(id, cart, storeId: 5),
        throwsA(isA<ProductNotSellableException>()));
    status = 422;
    await expectLater(
        api.createOrder(id, cart, storeId: 5), throwsA(isA<UnknownApiException>()));
    expect(await localOrders(), 0);
  });

  test('a cart with a coupon never becomes a local order', () async {
    await server.close(force: true);
    await expectLater(api.createOrder(id, cart, storeId: 5, couponCode: 'SAVE10'),
        throwsA(isA<NetworkException>()));
    await expectLater(api.quote(cart, storeId: 5, couponCode: 'SAVE10'),
        throwsA(isA<NetworkException>()));
    expect(await localOrders(), 0);
  });

  test('quote: server first, local price only when it cannot be reached', () async {
    body = {'subtotal': 3.0, 'tax': 0.45, 'total': 3.45, 'items': []};
    expect((await api.quote(cart, storeId: 5)).total, 3.45);
    status = 500;
    expect((await api.quote(cart, storeId: 5)).total, 4.03);
    status = 409;
    body = {'message': 'no'};
    await expectLater(api.quote(cart, storeId: 5),
        throwsA(isA<ProductNotSellableException>()));
  });

  test('cannot price locally (no device settings): the connection error stays',
      () async {
    await db.delete(db.deviceSettings).go();
    await server.close(force: true);
    await expectLater(
        api.createOrder(id, cart, storeId: 5), throwsA(isA<NetworkException>()));
    await expectLater(api.quote(cart, storeId: 5), throwsA(isA<NetworkException>()));
    expect(await localOrders(), 0);
  });

  test('a local order is paid locally; a server order is paid on the server',
      () async {
    status = 503;
    await api.createOrder(id, cart, storeId: 5); // local
    seen.clear();
    final r = await api.pay(id);
    expect(r.paid, isTrue);
    expect(seen, isEmpty); // no network call
    expect((await db.select(db.localOrders).getSingle()).status, 'PAID');

    status = 200;
    body = {'paid': true, 'status': 'PAID', 'order': {...serverOrder('other'), 'status': 'PAID'}};
    await api.pay('other');
    expect(seen.last, 'POST /api/orders/other/pay');
  });

  test('status of a local order is read locally, a server one from the server',
      () async {
    status = 503;
    await api.createOrder(id, cart, storeId: 5);
    seen.clear();
    expect((await api.getOrder(id)).orderId, id);
    expect(seen, isEmpty);
    status = 200;
    body = serverOrder('srv-1');
    expect((await api.getOrder('srv-1')).orderId, 'srv-1');
    expect(seen.single, 'GET /api/orders/srv-1');
  });

  test('off mode: the server only, no local fallback', () async {
    await LocalPrefs.saveConfig({'offline_mode': 'off'});
    await server.close(force: true);
    await expectLater(
        api.createOrder(id, cart, storeId: 5), throwsA(isA<NetworkException>()));
    expect(await localOrders(), 0);
  });

  group('approved card but the server cannot be told', () {
    Future<void> orderAndSession() async {
      body = serverOrder(id);
      await api.createOrder(id, cart, storeId: 5);
      body = {
        'id': 'sess-1', 'orderId': id, 'amount': 2.01, 'currency': 'SAR',
        'status': 'PENDING',
      };
      await api.createTerminalSession(id);
      seen.clear();
    }

    final notes = {'rrn': 'rrn-1', 'terminalId': 'T1'};

    test('server down: the payment is kept on the device and nothing is thrown',
        () async {
      await orderAndSession();
      await server.close(force: true);
      await api.confirmTerminalSession('sess-1', authCode: '123', notes: notes);
      final o = await db.select(db.localOrders).getSingle();
      expect(o.orderId, id);
      expect(o.status, 'PAID');
      expect(o.syncState, 'PAY_PENDING');
      final p = await db.select(db.localPayments).getSingle();
      expect(p.paymentId, 'sess-1');
      expect(p.providerReference, 'rrn-1');
      expect(p.syncedAt, isNull);
      // the invoice screen then reads the order: server lines, paid
      final shown = await api.getOrder(id);
      expect(shown.status, 'PAID');
      expect(shown.displayId, 501);
      expect(shown.invoiceUrl, 'http://srv/api/invoices/$id'); // plain link
    });

    test('server error 5xx on confirm is kept the same way', () async {
      await orderAndSession();
      status = 502;
      await api.confirmTerminalSession('sess-1', authCode: '123', notes: notes);
      expect((await db.select(db.localOrders).getSingle()).syncState, 'PAY_PENDING');
    });

    test('a 4xx on confirm is the server\'s answer: raised, nothing kept', () async {
      await orderAndSession();
      status = 409;
      body = {'message': 'expired'};
      await expectLater(
          api.confirmTerminalSession('sess-1', authCode: '123', notes: notes),
          throwsA(isA<UnknownApiException>()));
      expect(await localOrders(), 0);
    });

    test('server up: confirmed on the server, nothing kept locally', () async {
      await orderAndSession();
      body = {};
      await api.confirmTerminalSession('sess-1', authCode: '123', notes: notes);
      expect(seen.single, 'POST /api/terminal-sessions/sess-1/confirm');
      expect(await localOrders(), 0);
    });

    test('off mode: the failure is raised as before', () async {
      await orderAndSession();
      await LocalPrefs.saveConfig({'offline_mode': 'off'});
      await server.close(force: true);
      await expectLater(
          api.confirmTerminalSession('sess-1', authCode: '123', notes: notes),
          throwsA(isA<NetworkException>()));
      expect(await localOrders(), 0);
    });
  });
}
