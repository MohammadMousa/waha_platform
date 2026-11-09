import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/sync/device_settings.dart';

import '../generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('upgrading a version 1 database to the current one keeps data and adds the new table',
      () async {
    final schema = await verifier.schemaAt(1);
    // A v1 device that already pulled products.
    schema.rawDatabase.execute(
        "INSERT INTO local_products (id, name_json, price, price_with_vat, active, is_public, updated_at) "
        "VALUES (1, '{}', '5.00', '5.75', 1, 1, '2026-11-06T10:00:00Z')");
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    expect((await db.select(db.localProducts).get()).length, 1);
    expect(await readDeviceSettings(db), isNull);
    await db.close();
  });

  test('upgrading from version 2 adds the order tables and keeps device settings',
      () async {
    final schema = await verifier.schemaAt(2);
    schema.rawDatabase.execute(
        "INSERT INTO device_settings (id, device_id, device_no, store_id, organization_id, currency, vat_rate, prices_include_vat, fetched_at) "
        "VALUES (1, 3, 1, 5, 1, 'SAR', '0.15', 1, '2026-11-06T10:00:00Z')");
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    expect((await readDeviceSettings(db))!.deviceNo, 1);
    expect(await db.select(db.localOrders).get(), isEmpty);
    await db.close();
  });

  test('upgrading from version 3 keeps existing orders and adds the new columns', () async {
    final schema = await verifier.schemaAt(3);
    schema.rawDatabase.execute(
        "INSERT INTO local_orders (order_id, order_reference, store_id, status, currency, tax_rate, subtotal_amount, tax_amount, total_amount, created_at, sync_state, attempts) "
        "VALUES ('o1', 'WH-01-0001', 5, 'PAID', 'SAR', '0.15', '3.50', '0.53', '4.03', '2026-11-06T10:00:00Z', 'PENDING', 0)");
    schema.rawDatabase.execute(
        "INSERT INTO local_order_items (order_id, line_no, product_id, quantity, unit_price, line_net, line_tax) "
        "VALUES ('o1', 1, 11, 2, '1.75', '3.50', '0.53')");
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    final order = await db.select(db.localOrders).getSingle();
    expect(order.orderReference, 'WH-01-0001');
    expect(order.syncState, 'PENDING'); // a waiting order survives the upgrade
    final line = await db.select(db.localOrderItems).getSingle();
    expect(line.displayUnitPrice, isNull);
    await db.close();
  });

  test('upgrading from version 4 adds the payment sent flag; payments of sent orders count as sent',
      () async {
    final schema = await verifier.schemaAt(4);
    for (final r in [('o1', 'SYNCED'), ('o2', 'PENDING')]) {
      schema.rawDatabase.execute(
          "INSERT INTO local_orders (order_id, order_reference, store_id, status, currency, tax_rate, subtotal_amount, tax_amount, total_amount, created_at, sync_state, attempts, synced_at) "
          "VALUES ('${r.$1}', 'WH-${r.$1}', 5, 'PAID', 'SAR', '0.15', '3.50', '0.53', '4.03', '2026-11-06T10:00:00Z', '${r.$2}', 0, "
          "${r.$2 == 'SYNCED' ? "'2026-11-07T10:00:00Z'" : 'NULL'})");
      schema.rawDatabase.execute(
          "INSERT INTO local_payments (payment_id, order_id, provider, outcome, late_approval, created_at) "
          "VALUES ('p-${r.$1}', '${r.$1}', 'terminal', 'PAID', 0, '2026-11-06T10:01:00Z')");
    }
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    final pays = {
      for (final p in await db.select(db.localPayments).get()) p.orderId: p.syncedAt
    };
    expect(pays['o1'], '2026-11-07T10:00:00Z');
    expect(pays['o2'], isNull);
    await db.close();
  });

  test('upgrading from version 5 adds the resource cache table and keeps orders',
      () async {
    final schema = await verifier.schemaAt(5);
    schema.rawDatabase.execute(
        "INSERT INTO local_orders (order_id, order_reference, store_id, status, currency, tax_rate, subtotal_amount, tax_amount, total_amount, created_at, sync_state, attempts) "
        "VALUES ('o1', 'WH-01-0001', 5, 'PAID', 'SAR', '0.15', '3.50', '0.53', '4.03', '2026-11-06T10:00:00Z', 'PENDING', 0)");
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    expect((await db.select(db.localOrders).getSingle()).syncState, 'PENDING');
    expect(await db.select(db.cachedResources).get(), isEmpty);
    await db.close();
  });

  test('upgrading from version 6 adds the payment method icon column and keeps methods',
      () async {
    final schema = await verifier.schemaAt(6);
    schema.rawDatabase.execute(
        "INSERT INTO local_payment_methods (id, key, provider, offline_capable, active, sort_order, updated_at) "
        "VALUES (1, 'terminal', 'TERMINAL', 1, 1, 1, '2026-11-06T10:00:00Z')");
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    final m = await db.select(db.localPaymentMethods).getSingle();
    expect(m.key, 'terminal');
    expect(m.iconResourceId, isNull);
    await db.close();
  });

  test('device settings are saved, overwritten, and a blank short code becomes null',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    await saveDeviceConfig(db, {
      'deviceId': 3, 'deviceNo': 1, 'storeId': 5, 'organizationId': 1,
      'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
      'shortCode': '', 'lastReferenceSerial': null,
    });
    var s = (await readDeviceSettings(db))!;
    expect(s.deviceNo, 1);
    expect(s.vatRate, '0.15');
    expect(s.shortCode, isNull);
    expect(s.lastReferenceSerial, isNull);

    await saveDeviceConfig(db, {
      'deviceId': 3, 'deviceNo': 2, 'storeId': 5, 'organizationId': 1,
      'currency': 'SAR', 'vatRate': 0.15, 'pricesIncludeVat': true,
      'shortCode': 'WH', 'lastReferenceSerial': 233,
    });
    s = (await readDeviceSettings(db))!;
    expect(s.deviceNo, 2);
    expect(s.shortCode, 'WH');
    expect(s.lastReferenceSerial, 233);
    await db.close();
  });
}
