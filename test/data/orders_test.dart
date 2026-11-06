import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/orders/decimal.dart';
import 'package:waha_kiosk/data/orders/local_order_service.dart';
import 'package:waha_kiosk/data/orders/order_reference.dart';
import 'package:waha_kiosk/data/orders/pricing.dart';
import 'package:waha_kiosk/data/sync/device_settings.dart';

Map<String, dynamic> cfg({String? shortCode, int? last, int deviceNo = 1}) => {
      'deviceId': 3, 'deviceNo': deviceNo, 'storeId': 5, 'organizationId': 1,
      'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
      'shortCode': shortCode, 'lastReferenceSerial': last,
    };

void main() {
  group('decimal and pricing', () {
    test('rounds half-up, never to even', () {
      expect(Dec.parse('0.015').toFixed(2), '0.02');
      expect(Dec.parse('0.045').toFixed(2), '0.05');
      expect(Dec.parse('2.5').toFixed(0), '3');
      expect(Dec.parse('10').toFixed(2), '10.00');
    });

    test('a line is net plus its own tax, and lines add up to the total', () {
      // 3 x 1.75 = 5.25 net, tax 0.7875 -> 0.79, total 6.04.
      // (priceWithVat 2.01 x 3 = 6.03 would be 0.01 off: that is why it is never used.)
      final c = priceCart([const PricingInput(11, 3, '1.75')], vatRate: '0.15');
      expect(c.lines.single.net, '5.25');
      expect(c.lines.single.tax, '0.79');
      expect(c.subtotal, '5.25');
      expect(c.tax, '0.79');
      expect(c.total, '6.04');
    });

    test('tax is rounded per line, then summed', () {
      // Two lines of net 0.10: each tax 0.015 -> 0.02, total tax 0.04 (not 0.03).
      final c = priceCart([
        const PricingInput(1, 1, '0.10'),
        const PricingInput(2, 1, '0.10'),
      ], vatRate: '0.1500');
      expect(c.tax, '0.04');
      expect(c.subtotal, '0.20');
      expect(c.total, '0.24');
    });

    test('rejects an empty cart and a zero quantity', () {
      expect(() => priceCart([], vatRate: '0.15'), throwsArgumentError);
      expect(() => priceCart([const PricingInput(1, 0, '1.00')], vatRate: '0.15'),
          throwsArgumentError);
    });
  });

  group('order reference', () {
    test('shape, prefix fallback, and wrap', () {
      expect(buildReference(shortCode: 'WH', storeId: 5, deviceNo: 1, serial: 233), 'WH-01-0233');
      expect(buildReference(shortCode: null, storeId: 5, deviceNo: 12, serial: 7), '5-12-0007');
      expect(buildReference(shortCode: '', storeId: 5, deviceNo: 1, serial: 1), '5-01-0001');
      expect(nextSerial(null), 1);
      expect(nextSerial(232), 233);
      expect(nextSerial(9999), 0);
    });

    test('never longer than 30 characters', () {
      final ref = buildReference(
          shortCode: 'A' * 40, storeId: 5, deviceNo: 1, serial: 1);
      expect(ref.length, lessThanOrEqualTo(30));
    });
  });

  group('local orders', () {
    late AppDatabase db;
    late LocalOrderService svc;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      svc = LocalOrderService(db);
    });
    tearDown(() => db.close());

    const line = NewOrderLine(productId: 11, quantity: 3, unitPrice: '1.75');

    test('cannot create an order before the device settings were fetched', () async {
      expect(() => svc.createOrder(lines: [line]), throwsA(isA<MissingDeviceSettings>()));
    });

    test('references count up one per order, from the server value on a fresh install',
        () async {
      await saveDeviceConfig(db, cfg(shortCode: 'WH', last: 232));
      final a = await svc.createOrder(lines: [line], username: 'alj.kiosk');
      final b = await svc.createOrder(lines: [line]);
      expect(a.orderReference, 'WH-01-0233');
      expect(b.orderReference, 'WH-01-0234');
      expect(a.orderId == b.orderId, false);
      expect(a.status, 'CREATED');
      expect(a.syncState, 'LOCAL');
      expect(a.displayId, isNull);
      expect(a.totalAmount, '6.04');
    });

    test('the local counter wins over a stale server value afterwards', () async {
      await saveDeviceConfig(db, cfg(last: 10));
      await svc.createOrder(lines: [line]); // 11
      await saveDeviceConfig(db, cfg(last: 3)); // server value older than ours
      final o = await svc.createOrder(lines: [line]);
      expect(o.orderReference.endsWith('0012'), true);
    });

    test('marking paid saves one payment and queues the order; a repeat changes nothing',
        () async {
      await saveDeviceConfig(db, cfg(shortCode: 'WH'));
      final o = await svc.createOrder(lines: [line]);
      const pay = PaidPayment(
          provider: 'terminal',
          providerReference: 'rrn-1',
          authCode: '123456',
          notes: {'rrn': 'rrn-1', 'terminalId': 'T1'});
      await svc.markPaid(o.orderId, pay, paymentId: 'pay-1');
      await svc.markPaid(o.orderId, pay, paymentId: 'pay-1'); // callback fired twice
      final saved = await (db.select(db.localOrders)).getSingle();
      expect(saved.status, 'PAID');
      expect(saved.syncState, 'PENDING');
      expect((await db.select(db.localPayments).get()).length, 1);
    });

    test('push body matches the server contract', () async {
      await saveDeviceConfig(db, cfg(shortCode: 'WH', last: 232));
      final o = await svc.createOrder(lines: [line], username: 'alj.kiosk');
      await svc.markPaid(
          o.orderId,
          const PaidPayment(
              provider: 'terminal',
              providerReference: 'rrn-1',
              authCode: '123456',
              notes: {'rrn': 'rrn-1'},
              lateApproval: true),
          paymentId: 'pay-1');
      final b = await svc.buildPushBody(o.orderId);
      expect(b['orderReference'], 'WH-01-0233');
      expect(b['status'], 'PAID');
      expect(b['storeId'], 5);
      expect(b['taxRate'], 0.15);
      expect(b['subtotalAmount'], 5.25);
      expect(b['taxAmount'], 0.79);
      expect(b['totalAmount'], 6.04);
      expect(b.containsKey('displayId'), false);
      final item = (b['items'] as List).single as Map;
      expect(item, {'lineNo': 1, 'productId': 11, 'quantity': 3, 'unitPrice': 1.75});
      final p = (b['payments'] as List).single as Map;
      expect(p['paymentId'], 'pay-1');
      expect(p['authCode'], '123456');
      expect(p['lateApproval'], true);
      expect((p['notes'] as Map)['rrn'], 'rrn-1');
    });
  });
}
