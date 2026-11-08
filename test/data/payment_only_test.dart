import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/orders/local_order_service.dart';
import 'package:waha_kiosk/data/orders/order_push_service.dart';
import 'package:waha_kiosk/data/sync/device_settings.dart';
import 'package:waha_kiosk/models/order.dart';
import 'package:waha_kiosk/models/terminal_session.dart';

/// Orders the SERVER made (caching mode) whose card payment could not be
/// reported: the payment is kept and sent on its own. Order not sent -> the
/// whole order; order on the server but payment not -> payment only.
http.Response json(int code, Map<String, dynamic> b) =>
    http.Response(jsonEncode(b), code, headers: {'content-type': 'application/json'});

void main() {
  late AppDatabase db;
  late DateTime clock;
  late List<http.Request> sent;
  late http.Response Function(http.Request) respond;
  late LocalOrderService svc;
  const id = '0193aaaa-0000-7000-8000-0000000000aa';

  OrderPushService push() => OrderPushService.test(
        client: MockClient((req) async {
          sent.add(req);
          return respond(req);
        }),
        database: db,
        token: () => 'tok',
        now: () => clock,
      );

  Future<LocalOrder> byId(String o) =>
      (db.select(db.localOrders)..where((t) => t.orderId.equals(o))).getSingle();

  const order = WahaOrder(
      orderId: id, status: 'CREATED', subtotal: 3.5, tax: 0.53, total: 4.03,
      displayId: 501, items: [], currency: 'SAR');
  const session = TerminalSession(
      id: 'sess-1', orderId: id, amount: 4.03, currency: 'SAR', status: 'PENDING');
  const pay = PaidPayment(provider: 'terminal', authCode: '123', providerReference: 'rrn-1');

  Future<void> keep({WahaOrder? o = order}) => svc.keepPaymentOfServerOrder(
      orderId: id, pay: pay, paymentId: 'sess-1', order: o, session: session);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clock = DateTime.utc(2026, 11, 8, 10);
    sent = [];
    svc = LocalOrderService(db, now: () => clock);
    await saveDeviceConfig(db, {
      'deviceId': 3, 'deviceNo': 1, 'storeId': 5, 'organizationId': 1,
      'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
      'shortCode': 'WH', 'lastReferenceSerial': null,
    });
    respond = (r) => json(200, {'result': 'UPDATED', 'orderId': id, 'displayId': 501});
  });
  tearDown(() => db.close());

  test('the approved payment is kept first: order PAID, to be sent as a payment only',
      () async {
    await keep();
    final o = await byId(id);
    expect(o.status, 'PAID');
    expect(o.syncState, 'PAY_PENDING');
    expect(o.totalAmount, '4.03');
    expect(o.displayId, 501);
    final p = await db.select(db.localPayments).getSingle();
    expect(p.paymentId, 'sess-1');
    expect(p.outcome, 'PAID');
    expect(p.syncedAt, isNull);
    await keep(); // the same payment again changes nothing
    expect((await db.select(db.localPayments).get()).length, 1);
  });

  test('without the remembered order the record is built from the session',
      () async {
    await keep(o: null);
    final o = await byId(id);
    expect(o.totalAmount, '4.03');
    expect(o.syncState, 'PAY_PENDING');
  });

  test('the payment-only send: right address and body, then everything is marked sent',
      () async {
    await keep();
    final r = await push().pushPending();
    expect(r.count, 1);
    expect(sent.single.url.path, '/api/sync/orders/$id/payments');
    expect(sent.single.headers['Authorization'], 'Bearer tok');
    final b = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(b['totalAmount'], 4.03);
    expect(b.containsKey('items'), isFalse); // the lines are not part of it
    final p = (b['payments'] as List).single as Map<String, dynamic>;
    expect(p['paymentId'], 'sess-1');
    expect(p['providerReference'], 'rrn-1');
    expect(p['authCode'], '123');
    expect(p['outcome'], 'PAID');
    final o = await byId(id);
    expect(o.syncState, 'SYNCED');
    expect(o.displayId, 501);
    expect((await db.select(db.localPayments).getSingle()).syncedAt, isNotNull);
    // both synced: nothing more is sent
    sent.clear();
    await push().pushPending();
    expect(sent, isEmpty);
  });

  test('ALREADY_SYNCED is a success too, and repeating is safe', () async {
    respond = (r) => json(200, {'result': 'ALREADY_SYNCED', 'orderId': id, 'displayId': 501});
    await keep();
    await push().pushPending();
    expect((await byId(id)).syncState, 'SYNCED');
  });

  test('404 / 409 / 422 go to the failed list and are not retried by themselves',
      () async {
    for (final c in [
      (404, 'ORDER_NOT_FOUND'),
      (409, 'PAYMENT_CONFLICT'),
      (409, 'STORE_MISMATCH'),
      (409, 'ORDER_CANCELLED_ON_SERVER'),
      (422, 'PAYMENT_MISSING'),
      (422, 'INVALID_REQUEST'),
    ]) {
      await db.delete(db.localPayments).go();
      await db.delete(db.localOrders).go();
      await keep();
      respond = (r) => json(c.$1, {'error': c.$2, 'message': 'm', 'retryable': false});
      final res = await push().pushPending();
      expect(res.rejected, 1, reason: c.$2);
      final o = await byId(id);
      expect(o.syncState, 'DEAD', reason: c.$2);
      expect(o.lastErrorCode, c.$2);
    }
  });

  test('server trouble: stays waiting and backs off', () async {
    await keep();
    respond = (r) => json(503, {'error': 'X', 'message': 'busy'});
    final res = await push().pushPending();
    expect(res.kind.name, 'failed');
    final o = await byId(id);
    expect(o.syncState, 'PAY_PENDING');
    expect(o.attempts, 1);
    expect(o.nextAttemptAt, isNotNull);
    // not due yet: nothing is sent
    sent.clear();
    await push().pushPending();
    expect(sent, isEmpty);
    // later it goes through
    clock = clock.add(const Duration(hours: 1));
    respond = (r) => json(200, {'result': 'UPDATED', 'orderId': id, 'displayId': 501});
    await push().pushPending();
    expect((await byId(id)).syncState, 'SYNCED');
  });

  test('Retry on a record without lines sends the payment, never a whole order',
      () async {
    await keep();
    respond = (r) => json(404, {'error': 'ORDER_NOT_FOUND', 'message': 'm'});
    await push().pushPending();
    expect((await byId(id)).syncState, 'DEAD');
    final service = push();
    await service.retryDead(id);
    expect((await byId(id)).syncState, 'PAY_PENDING');
  });

  test('the waiting count includes payments waiting to be sent', () async {
    await keep();
    final c = await orderCounts(db);
    expect(c.pending, 1);
  });

  test('a whole order that is accepted marks its payments as sent', () async {
    final o = await svc.createOrder(lines: const [
      NewOrderLine(productId: 11, quantity: 2, unitPrice: '5.00'),
    ]);
    await svc.markPaid(o.orderId, pay, paymentId: 'p-1');
    respond = (r) => json(200, {'result': 'CREATED', 'displayId': 9});
    await push().pushPending();
    expect(sent.single.url.path, '/api/sync/orders');
    expect((await db.select(db.localPayments).getSingle()).syncedAt, isNotNull);
  });

  test('a new payment on an order the server already holds is sent on its own',
      () async {
    final o = await svc.createOrder(lines: const [
      NewOrderLine(productId: 11, quantity: 2, unitPrice: '5.00'),
    ]);
    await svc.markPaid(o.orderId, pay, paymentId: 'p-1');
    respond = (r) => json(200, {'result': 'CREATED', 'displayId': 9});
    await push().pushPending(); // order + p-1 sent
    sent.clear();
    // a late approval is a second payment on the same, already sent order
    await svc.markPaid(
        o.orderId,
        const PaidPayment(
            provider: 'terminal', providerReference: 'rrn-late', lateApproval: true),
        paymentId: 'p-2');
    expect((await byId(o.orderId)).syncState, 'PAY_PENDING');
    respond = (r) => json(200, {'result': 'UPDATED', 'displayId': 9});
    await push().pushPending();
    expect(sent.single.url.path, '/api/sync/orders/${o.orderId}/payments');
    final b = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect((b['payments'] as List).length, 1); // only the new one
    expect(((b['payments'] as List).single as Map)['paymentId'], 'p-2');
    expect((await byId(o.orderId)).syncState, 'SYNCED');
  });
}
