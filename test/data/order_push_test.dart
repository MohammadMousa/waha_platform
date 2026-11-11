import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/orders/local_order_service.dart';
import 'package:waha_kiosk/data/orders/order_push_service.dart';
import 'package:waha_kiosk/data/sync/device_settings.dart';
import 'package:waha_kiosk/data/sync/sync_settings.dart';

http.Response json(int code, Map<String, dynamic> b) =>
    http.Response(jsonEncode(b), code, headers: {'content-type': 'application/json'});

class _Max implements Random {
  @override
  double nextDouble() => 1.0;
  @override
  int nextInt(int max) => max - 1;
  @override
  bool nextBool() => true;
}

void main() {
  group('classifying the server answer', () {
    test('success keeps the server order number', () {
      final o = classifyPushResponse(200,
          '{"result":"CREATED","orderId":"x","displayId":96073,"orderReference":"WH-01-0233"}');
      expect(o, isA<PushAccepted>());
      expect((o as PushAccepted).displayId, 96073);
      expect(classifyPushResponse(200, '{"result":"ALREADY_SYNCED","displayId":5}'),
          isA<PushAccepted>());
    });

    test('permanent errors go to the dead-letter list', () {
      for (final c in [
        (422, 'TOTALS_MISMATCH'),
        (422, 'PRODUCT_NOT_FOUND'),
        (409, 'ITEMS_CONFLICT'),
        (409, 'ORDER_CANCELLED_ON_SERVER'),
      ]) {
        final o = classifyPushResponse(
            c.$1, '{"error":"${c.$2}","message":"m","retryable":false}');
        expect(o, isA<PushRejected>());
        expect((o as PushRejected).code, c.$2);
      }
      expect(classifyPushResponse(400, ''), isA<PushRejected>());
    });

    test('server trouble and throttling are retried', () {
      expect(classifyPushResponse(500, 'oops'), isA<PushRetry>());
      expect(classifyPushResponse(502, '<html>bad gateway</html>'), isA<PushRetry>());
      expect(classifyPushResponse(408, ''), isA<PushRetry>());
      expect(classifyPushResponse(429, ''), isA<PushRetry>());
    });

    test('401 and 403 stop the push without judging the order', () {
      expect(classifyPushResponse(401, ''), isA<PushAuthStop>());
      expect(classifyPushResponse(403, ''), isA<PushAuthStop>());
    });
  });

  test('back-off doubles per attempt and stops at the cap', () {
    const base = Duration(minutes: 3);
    const max = Duration(minutes: 15);
    expect(pushBackoff(1, base, max), const Duration(minutes: 6));
    expect(pushBackoff(2, base, max), const Duration(minutes: 12));
    expect(pushBackoff(3, base, max), max);
    expect(pushBackoff(500, base, max), max);
  });

  group('pushing orders', () {
    late AppDatabase db;
    late DateTime clock;
    late List<http.Request> sent;
    late http.Response Function(http.Request) respond;
    String? token = 'tok';

    OrderPushService makeService() => OrderPushService.test(
          client: MockClient((req) async {
            sent.add(req);
            return respond(req);
          }),
          database: db,
          token: () => token,
          now: () => clock,
        );

    Future<LocalOrder> paidOrder(LocalOrderService svc, {String pid = 'p'}) async {
      clock = clock.add(const Duration(minutes: 1));
      final o = await svc.createOrder(lines: const [
        NewOrderLine(productId: 11, quantity: 2, unitPrice: '5.00'),
      ]);
      await svc.markPaid(
          o.orderId,
          const PaidPayment(provider: 'terminal', authCode: '1', providerReference: 'r'),
          paymentId: '$pid-${o.orderId}');
      return o;
    }

    Future<LocalOrder> byId(String id) =>
        (db.select(db.localOrders)..where((t) => t.orderId.equals(id))).getSingle();

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      clock = DateTime.utc(2026, 11, 6, 10);
      sent = [];
      token = 'tok';
      await saveDeviceConfig(db, {
        'deviceId': 3, 'deviceNo': 1, 'storeId': 5, 'organizationId': 1,
        'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
        'shortCode': 'WH', 'lastReferenceSerial': null,
      });
      respond = (r) => json(200, {'result': 'CREATED', 'displayId': 96073});
    });
    tearDown(() => db.close());

    test('an accepted order becomes SYNCED with the server number, and is sent with the token',
        () async {
      final svc = LocalOrderService(db, now: () => clock);
      final o = await paidOrder(svc);
      await makeService().pushPending();
      expect(sent.length, 1);
      expect(sent.single.headers['Authorization'], 'Bearer tok');
      expect(sent.single.url.path, '/api/sync/orders');
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['orderId'], o.orderId);
      expect(body['orderReference'], 'WH-01-0001');
      final saved = await byId(o.orderId);
      expect(saved.syncState, 'SYNCED');
      expect(saved.displayId, 96073);
      expect(saved.syncedAt, isNotNull);
      expect(saved.orderReference, 'WH-01-0001'); // what the customer saw stays
    });

    group('sending one unpaid order before a QR payment', () {
      Future<LocalOrder> unpaid(LocalOrderService svc) => svc.createOrder(lines: const [
            NewOrderLine(productId: 11, quantity: 2, unitPrice: '5.00'),
          ]);

      test('is sent once as unpaid with no payments, then marked sent', () async {
        final svc = LocalOrderService(db, now: () => clock);
        final o = await unpaid(svc);
        final push = makeService();
        expect(await push.sendUnpaidNow(o.orderId), UnpaidSendResult.onServer);
        final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
        expect(body['status'], 'CREATED');
        expect(body['payments'], isEmpty);
        final saved = await byId(o.orderId);
        expect(saved.syncState, 'SYNCED');
        expect(saved.displayId, 96073);
        // Asking again, or the normal pass, never sends it a second time.
        expect(await push.sendUnpaidNow(o.orderId), UnpaidSendResult.onServer);
        await push.pushPending();
        expect(sent.length, 1);
      });

      test('no connection: nothing changes and the customer can be told', () async {
        final svc = LocalOrderService(db, now: () => clock);
        final o = await unpaid(svc);
        respond = (r) => throw http.ClientException('no route to host');
        expect(await makeService().sendUnpaidNow(o.orderId), UnpaidSendResult.noConnection);
        final saved = await byId(o.orderId);
        expect(saved.syncState, 'LOCAL'); // not failed, no retry time
        expect(saved.nextAttemptAt, isNull);
      });

      test('a server refusal is reported and does not dead-letter the unpaid order', () async {
        final svc = LocalOrderService(db, now: () => clock);
        final o = await unpaid(svc);
        respond = (r) => json(422, {'error': 'PRODUCT_NOT_FOUND', 'message': 'm', 'retryable': false});
        expect(await makeService().sendUnpaidNow(o.orderId), UnpaidSendResult.refused);
        expect((await byId(o.orderId)).syncState, 'LOCAL');
      });

      test('an order made on the server (no local copy) needs nothing', () async {
        expect(await makeService().sendUnpaidNow('not-here'), UnpaidSendResult.onServer);
        expect(sent, isEmpty);
      });

      test('after a QR payment the local copy is paid and nothing more is sent', () async {
        final svc = LocalOrderService(db, now: () => clock);
        final o = await unpaid(svc);
        final push = makeService();
        await push.sendUnpaidNow(o.orderId);
        await svc.markPaidOnServer(o.orderId, displayId: 96074);
        final saved = await byId(o.orderId);
        expect(saved.status, 'PAID');
        expect(saved.paidAt, isNotNull);
        expect(saved.syncState, 'SYNCED');
        expect(saved.displayId, 96074);
        expect(await db.select(db.localPayments).get(), isEmpty); // the server holds the payment
        await push.pushPending();
        expect(sent.length, 1);
      });

      test('a card payment on an order sent unpaid sends the payment only', () async {
        final svc = LocalOrderService(db, now: () => clock);
        final o = await unpaid(svc);
        final push = makeService();
        await push.sendUnpaidNow(o.orderId);
        await svc.markPaid(
            o.orderId, const PaidPayment(provider: 'terminal', authCode: '1', providerReference: 'r'),
            paymentId: 'p1');
        expect((await byId(o.orderId)).syncState, 'PAY_PENDING');
        await push.pushPending();
        expect(sent.last.url.path, '/api/sync/orders/${o.orderId}/payments');
      });
    });

    test('unpaid orders are never sent', () async {
      final svc = LocalOrderService(db, now: () => clock);
      await svc.createOrder(lines: const [
        NewOrderLine(productId: 11, quantity: 1, unitPrice: '5.00'),
      ]);
      await makeService().pushPending();
      expect(sent, isEmpty);
    });

    test('a rejected order is dead-lettered and the next one is still sent', () async {
      final svc = LocalOrderService(db, now: () => clock);
      final a = await paidOrder(svc);
      final b = await paidOrder(svc);
      var n = 0;
      respond = (r) => (n++ == 0)
          ? json(422, {'error': 'TOTALS_MISMATCH', 'message': 'bad', 'retryable': false})
          : json(200, {'result': 'CREATED', 'displayId': 7});
      await makeService().pushPending();
      expect(sent.length, 2);
      final da = await byId(a.orderId);
      expect(da.syncState, 'DEAD');
      expect(da.lastErrorCode, 'TOTALS_MISMATCH');
      expect((await byId(b.orderId)).syncState, 'SYNCED');
      final counts = await orderCounts(db);
      expect((counts.pending, counts.dead), (0, 1));
    });

    test('a server error keeps the order pending with a back-off and stops the pass',
        () async {
      final svc = LocalOrderService(db, now: () => clock);
      final a = await paidOrder(svc);
      final b = await paidOrder(svc);
      respond = (r) => http.Response('down', 503);
      final push = makeService();
      await push.pushPending();
      expect(sent.length, 1); // did not hammer with the second order
      final ra = await byId(a.orderId);
      expect(ra.syncState, 'PENDING');
      expect(ra.attempts, 1);
      expect(DateTime.parse(ra.nextAttemptAt!).isAfter(clock), true);
      expect((await byId(b.orderId)).attempts, 0);

      // The first order waits out its back-off; the untouched second one is
      // due, so only it is tried (and it backs off too, server still down).
      sent.clear();
      await push.pushPending();
      expect(sent.length, 1);
      expect((jsonDecode(sent.single.body) as Map)['orderId'], b.orderId);
      expect((await byId(a.orderId)).attempts, 1);
      expect((await byId(b.orderId)).attempts, 1);

      // Time passes and the server is back: both go through, oldest first.
      sent.clear();
      clock = clock.add(const Duration(hours: 1));
      respond = (r) => json(200, {'result': 'CREATED', 'displayId': 1});
      await push.pushPending();
      expect(sent.length, 2);
      expect((await orderCounts(db)).pending, 0);
    });

    test('a network failure is a retry, not a rejection', () async {
      final svc = LocalOrderService(db, now: () => clock);
      final a = await paidOrder(svc);
      final push = OrderPushService.test(
        client: MockClient((req) async => throw Exception('no route')),
        database: db,
        token: () => token,
        now: () => clock,
      );
      await push.pushPending();
      final r = await byId(a.orderId);
      expect(r.syncState, 'PENDING');
      expect(r.lastError, contains('network'));
    });

    test('401 stops everything, keeps the orders and does not mark them failed', () async {
      final svc = LocalOrderService(db, now: () => clock);
      final a = await paidOrder(svc);
      await paidOrder(svc);
      respond = (r) => http.Response('', 401);
      final push = makeService();
      await push.pushPending();
      expect(sent.length, 1);
      expect(push.authBlocked, true);
      expect((await byId(a.orderId)).syncState, 'PENDING');
      expect((await byId(a.orderId)).attempts, 0);
      // Signed in again: the warning clears on the first accepted push.
      respond = (r) => json(200, {'result': 'CREATED', 'displayId': 1});
      await push.pushPending();
      expect(push.authBlocked, false);
      expect((await orderCounts(db)).pending, 0);
    });

    test('without a token nothing is sent', () async {
      final svc = LocalOrderService(db, now: () => clock);
      await paidOrder(svc);
      token = null;
      await makeService().pushPending();
      expect(sent, isEmpty);
    });

    test('Retry puts a dead-lettered order back in the queue', () async {
      final svc = LocalOrderService(db, now: () => clock);
      final a = await paidOrder(svc);
      respond = (r) => json(409, {'error': 'ORDER_CANCELLED_ON_SERVER', 'message': 'x', 'retryable': false});
      final push = makeService();
      await push.pushPending();
      expect((await push.deadOrders()).length, 1);
      await push.retryDead(a.orderId);
      expect((await byId(a.orderId)).syncState, 'PENDING');
      expect((await push.deadOrders()), isEmpty);
      respond = (r) => json(200, {'result': 'CREATED', 'displayId': 9});
      await push.pushPending();
      expect((await byId(a.orderId)).syncState, 'SYNCED');
    });

    test('a dead-lettered order is not revived by a repeated payment callback', () async {
      final svc = LocalOrderService(db, now: () => clock);
      final a = await paidOrder(svc);
      respond = (r) => json(422, {'error': 'PRODUCT_NOT_FOUND', 'message': 'x', 'retryable': false});
      await makeService().pushPending();
      await svc.markPaid(a.orderId, const PaidPayment(provider: 'terminal'),
          paymentId: 'another');
      expect((await byId(a.orderId)).syncState, 'DEAD');
    });
  });

  group('scheduling rules for retries', () {
    late AppDatabase db;
    late DateTime clock;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      clock = DateTime.utc(2026, 11, 6, 10);
      await saveDeviceConfig(db, {
        'deviceId': 3, 'deviceNo': 1, 'storeId': 5, 'organizationId': 1,
        'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
        'shortCode': 'WH', 'lastReferenceSerial': null,
      });
    });
    tearDown(() => db.close());

    Future<LocalOrder> paid() async {
      final svc = LocalOrderService(db, now: () => clock);
      final o = await svc.createOrder(lines: const [
        NewOrderLine(productId: 11, quantity: 1, unitPrice: '5.00'),
      ]);
      await svc.markPaid(o.orderId, const PaidPayment(provider: 'terminal'), paymentId: 'p-${o.orderId}');
      return o;
    }

    Future<LocalOrder> byId(String id) =>
        (db.select(db.localOrders)..where((t) => t.orderId.equals(id))).getSingle();

    test('a failed order waits its back-off plus up to 20% jitter, and the first try is never delayed',
        () async {
      final o = await paid();
      final push = OrderPushService.test(
        client: MockClient((r) async => http.Response('down', 503)),
        database: db, token: () => 'tok', now: () => clock,
        random: _Max(), // maximum jitter
      );
      await push.pushPending(); // first try happened at once
      final r = await byId(o.orderId);
      // base 3 min doubled once = 6 min, +20% = 7.2 min.
      expect(DateTime.parse(r.nextAttemptAt!).difference(clock),
          const Duration(minutes: 7, seconds: 12));
    });

    test('a Retry-After longer than the back-off wins', () async {
      final o = await paid();
      final push = OrderPushService.test(
        client: MockClient((r) async => http.Response('busy', 503, headers: {'retry-after': '1200'})),
        database: db, token: () => 'tok', now: () => clock, random: _Max(),
      );
      await push.pushPending();
      expect(DateTime.parse((await byId(o.orderId)).nextAttemptAt!).difference(clock),
          const Duration(minutes: 20));
    });

    test('an order whose retry time is absurdly far ahead (clock set back) is sent now', () async {
      final o = await paid();
      await (db.update(db.localOrders)..where((t) => t.orderId.equals(o.orderId))).write(
          LocalOrdersCompanion(nextAttemptAt: Value(clock.add(const Duration(days: 30)).toIso8601String())));
      var sent = 0;
      final push = OrderPushService.test(
        client: MockClient((r) async {
          sent++;
          return json(200, {'result': 'CREATED', 'displayId': 1});
        }),
        database: db, token: () => 'tok', now: () => clock,
      );
      await push.pushPending();
      expect(sent, 1);
    });

    test('the network callback reports reachable and unreachable', () async {
      await paid();
      final seen = <bool>[];
      var fail = true;
      final push = OrderPushService.test(
        client: MockClient((r) async {
          if (fail) throw Exception('no route');
          return json(200, {'result': 'CREATED', 'displayId': 1});
        }),
        database: db, token: () => 'tok', now: () => clock,
      );
      push.start(db, settings: () => const SyncSettings(), onNetwork: seen.add);
      push.stop();
      await push.pushPending();
      fail = false;
      clock = clock.add(const Duration(hours: 1));
      await push.pushPending();
      expect(seen, [false, true]);
    });
  });

  test('push settings come from /api/config', () {
    final s = SyncSettings.fromConfig({
      'sync_push_interval_minutes': '5',
      'sync_push_timeout_seconds': '20',
      'sync_push_retry_max_delay_minutes': '5',
      'offline_mode': 'true',
    });
    expect(s.pushInterval, const Duration(minutes: 5));
    expect(s.pushTimeout, const Duration(seconds: 20));
    expect(s.pushRetryMaxDelay, const Duration(minutes: 5));
    expect(s.offlineMode, true);
    expect(const SyncSettings().pushInterval, const Duration(minutes: 3));
    expect(const SyncSettings().interval, const Duration(minutes: 60));
  });
}
