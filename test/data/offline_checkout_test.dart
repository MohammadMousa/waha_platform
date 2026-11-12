import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/data/catalog/local_catalog.dart';
import 'package:waha_kiosk/data/catalog/offline_mode.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/orders/local_order_service.dart';
import 'package:waha_kiosk/data/sync/device_settings.dart';
import 'package:waha_kiosk/data/sync/feeds.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/api_exceptions.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/state/order_flow_controller.dart';
import 'package:waha_kiosk/state/store_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The scan sound uses a platform plugin that does not exist in tests.
  for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }

  late AppDatabase db;
  late ApiClient api;
  late OrderFlowController flow;

  Future<List<LocalPayment>> payments() => db.select(db.localPayments).get();
  Future<LocalOrder> orderRow(String id) =>
      (db.select(db.localOrders)..where((t) => t.orderId.equals(id))).getSingle();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    await LocalPrefs.setOfflineMode(true);
    storeConfigService.setStoreId(5, persist: false);
    db = AppDatabase(NativeDatabase.memory());
    await upsertPage(db, 'products', [
      {
        'id': 11, 'barcode': 'B11', 'sku': null,
        'name': {'en': 'Salad', 'ar': 'سلطة'}, 'description': null,
        'price': '1.75', 'priceWithVat': '2.01', 'active': true, 'public': true,
        'categoryId': null, 'imageResourceId': null, 'updatedAt': 'x',
      },
    ]);
    await upsertPage(db, 'barcodes', [
      {'id': 1, 'productId': 11, 'barcode': 'B11', 'primary': true, 'updatedAt': 'x'},
    ]);
    await upsertPage(db, 'payment-methods', [
      {'id': 1, 'key': 'terminal', 'displayName': {'en': 'Card'}, 'provider': 'TERMINAL',
       'availableModes': 'KIOSK', 'offlineCapable': true, 'active': true, 'sortOrder': 1,
       'paymentUrl': null, 'updatedAt': 'x'},
      {'id': 2, 'key': 'stripe', 'displayName': {'en': 'Online'}, 'provider': 'REDIRECT',
       'availableModes': 'KIOSK', 'offlineCapable': false, 'active': true, 'sortOrder': 2,
       'paymentUrl': null, 'updatedAt': 'x'},
    ]);
    for (final f in kRequiredFeeds) {
      await db.into(db.syncState).insertOnConflictUpdate(
          SyncStateCompanion(feed: Value(f), fullPullDone: const Value(true)));
    }
    await saveDeviceConfig(db, {
      'deviceId': 3, 'deviceNo': 1, 'storeId': 5, 'organizationId': 1,
      'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
      'shortCode': 'WH', 'lastReferenceSerial': 232,
      'invoiceBaseUrl': 'http://192.168.1.42:8081',
    });
    OfflineMode.catalog = LocalCatalog(db);
    OfflineMode.orders = LocalOrderService(db);
    OfflineMode.sessionOrder.clear();
    api = ApiClient(baseUrl: 'http://127.0.0.1:1'); // unreachable: must never be used
    flow = OrderFlowController(api);
  });

  tearDown(() async {
    OfflineMode.catalog = null;
    OfflineMode.orders = null;
    await db.close();
  });

  Future<String> checkoutOne({int qty = 2}) async {
    for (var i = 0; i < qty; i++) {
      await flow.scanBarcode('B11');
    }
    final order = await flow.checkout();
    return order.orderId;
  }

  test('scan, cart and checkout work with the server unreachable', () async {
    final id = await checkoutOne();
    final o = flow.order!;
    expect(o.orderId, id);
    expect(o.status, 'CREATED');
    expect(o.orderReference, 'WH-01-0233');
    expect(o.displayId, isNull);
    expect(o.displayNumber, '\u2066WH-01-0233\u2069'); // shown instead of a number the server has not given yet
    expect(o.total, 4.03);
    expect(o.subtotal, 3.50);
    expect(o.tax, 0.53);
    expect(o.items.single.unitPrice, 2.01);
    expect(o.items.single.lineTotal, 4.03);
    expect(o.invoiceUrl, 'http://192.168.1.42:8081/api/invoices/$id?offline=1');
    expect(flow.cart, isEmpty);
  });

  test('checking out again with the same order id gives the same order, not a second one',
      () async {
    final id = await checkoutOne(qty: 1);
    await flow.scanBarcode('B11');
    final again = await api.createOrder(id, flow.cart);
    expect(again.orderId, id);
    expect((await db.select(db.localOrders).get()).length, 1);
  });

  test('the invoice screen reads the local order and the offline payment methods', () async {
    final id = await checkoutOne();
    expect((await api.getOrder(id)).status, 'CREATED');
    final methods = await api.getPaymentMethods(mode: 'KIOSK', storeId: 5);
    expect([for (final m in methods) m.key], ['terminal']); // the online-only one is hidden
  });

  test('terminal approval: payment saved locally, order PAID and queued, nothing sent to a server',
      () async {
    final id = await checkoutOne();
    final session = await api.createTerminalSession(id);
    expect(session.amount, 4.03);
    await api.confirmTerminalSession(session.id,
        authCode: '123456', notes: {'rrn': 'RRN-1', 'terminalId': 'T1', 'vendor': 'geidea'});
    final paid = await api.getOrder(id);
    expect(paid.status, 'PAID');
    expect(paid.paymentMethod, 'terminal');
    final row = await orderRow(id);
    expect(row.syncState, 'PENDING');
    final p = (await payments()).single;
    expect(p.paymentId, session.id);
    expect(p.authCode, '123456');
    expect(jsonDecode(p.notesJson!)['rrn'], 'RRN-1');
    expect(p.lateApproval, false);
    // the push body carries it
    final body = await OfflineMode.orders!.buildPushBody(id);
    expect(body['orderReference'], 'WH-01-0233');
    expect(body.containsKey('displayId'), false);
    expect(((body['payments'] as List).single as Map)['providerReference'], 'RRN-1');
  });

  test('a repeated callback for the same terminal transaction is one payment', () async {
    final id = await checkoutOne();
    final s1 = await api.createTerminalSession(id);
    await api.confirmTerminalSession(s1.id, authCode: '1', notes: {'rrn': 'RRN-1'});
    // a late-approval report for the SAME transaction arrives afterwards
    final result = await api.reportLateApproval(id, amount: 4.03, rrn: 'RRN-1');
    expect(result, 'PAID');
    expect((await payments()).length, 1);
  });

  test('a cancelled or declined terminal attempt saves no payment', () async {
    final id = await checkoutOne();
    final s = await api.createTerminalSession(id);
    await api.cancelTerminalSession(s.id);
    expect(await payments(), isEmpty);
    expect((await orderRow(id)).status, 'CREATED');
    expect((await orderRow(id)).syncState, 'LOCAL');
  });

  test('a paid order cannot open another terminal session', () async {
    final id = await checkoutOne();
    final s = await api.createTerminalSession(id);
    await api.confirmTerminalSession(s.id, authCode: '1', notes: {'rrn': 'R'});
    await expectLater(api.createTerminalSession(id), throwsA(isA<OrderAlreadyPaidException>()));
  });

  test('a late approval after the kiosk gave up marks the order paid, flagged late', () async {
    final id = await checkoutOne();
    final s = await api.createTerminalSession(id);
    await api.cancelTerminalSession(s.id); // customer gave up / timeout
    final result = await api.reportLateApproval(id,
        amount: 4.03, rrn: 'RRN-9', approvalCode: 'AP9', terminalId: 'T1');
    expect(result, 'PAID');
    final row = await orderRow(id);
    expect(row.status, 'PAID');
    expect(row.syncState, 'PENDING');
    final p = (await payments()).single;
    expect(p.lateApproval, true);
    expect(p.providerReference, 'RRN-9');
    // reported twice: still one payment
    await api.reportLateApproval(id, amount: 4.03, rrn: 'RRN-9');
    expect((await payments()).length, 1);
  });

  test('simulated payment: success pays locally, decline saves nothing', () async {
    final id = await checkoutOne();
    final declined = await api.pay(id, simulateOutcome: 'DECLINED');
    expect(declined.paid, false);
    expect(await payments(), isEmpty);
    final ok = await api.pay(id, simulateOutcome: 'SUCCESS');
    expect(ok.paid, true);
    expect(ok.order.status, 'PAID');
    expect((await payments()).single.provider, 'simulated');
  });

  test('the order reference counts up per order and the unpaid ones stay local', () async {
    final a = await checkoutOne(qty: 1);
    flow.reset();
    final b = await checkoutOne(qty: 1);
    expect((await orderRow(a)).orderReference, 'WH-01-0233');
    expect((await orderRow(b)).orderReference, 'WH-01-0234');
    expect((await orderRow(b)).syncState, 'LOCAL'); // unpaid: never queued for the server
  });

  test('before the first full pull the offline flow says so instead of selling', () async {
    await db.delete(db.syncState).go();
    await expectLater(flow.scanBarcode('B11'), throwsA(isA<OfflineNotReadyException>()));
  });

  test('with offline mode off, nothing here is used (the server is asked, and is unreachable)',
      () async {
    await LocalPrefs.setOfflineMode(false);
    // (the product IS in the local database, so any failure proves the server path was taken)
    await expectLater(flow.scanBarcode('B11'), throwsA(isNotNull));
  });
}
