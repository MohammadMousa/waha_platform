import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/orders/order_cleanup.dart';
import 'package:waha_kiosk/data/sync/sync_settings.dart';

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 11, 30, 12);
  String ago(int days) => now.subtract(Duration(days: days)).toIso8601String();

  Future<void> order(String id,
      {required String status, required String sync, required int daysOld, int? syncedDaysAgo}) async {
    await db.into(db.localOrders).insert(LocalOrdersCompanion.insert(
          orderId: id, orderReference: 'R-$id', storeId: 5, status: status, currency: 'SAR',
          taxRate: '0.15', subtotalAmount: '1.00', taxAmount: '0.15', totalAmount: '1.15',
          createdAt: ago(daysOld), syncState: Value(sync),
          syncedAt: Value(syncedDaysAgo == null ? null : ago(syncedDaysAgo)),
        ));
    await db.into(db.localOrderItems).insert(LocalOrderItemsCompanion.insert(
        orderId: id, lineNo: 1, productId: 1, quantity: 1, unitPrice: '1.00', lineNet: '1.00', lineTax: '0.15'));
    if (status == 'PAID') {
      await db.into(db.localPayments).insert(LocalPaymentsCompanion.insert(
          paymentId: 'p-$id', orderId: id, provider: 'terminal', outcome: 'PAID', createdAt: ago(daysOld)));
    }
  }

  Future<Set<String>> ids() async =>
      {for (final o in await db.select(db.localOrders).get()) o.orderId};

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await order('unpaid-old', status: 'CREATED', sync: 'LOCAL', daysOld: 20);
    await order('unpaid-new', status: 'CREATED', sync: 'LOCAL', daysOld: 3);
    await order('pending-old', status: 'PAID', sync: 'PENDING', daysOld: 40);
    await order('dead-old', status: 'PAID', sync: 'DEAD', daysOld: 40);
    await order('sent-old', status: 'PAID', sync: 'SYNCED', daysOld: 40, syncedDaysAgo: 39);
    await order('sent-new', status: 'PAID', sync: 'SYNCED', daysOld: 40, syncedDaysAgo: 2);
  });
  tearDown(() => db.close());

  test('both rules are off by default: nothing is deleted', () async {
    final r = await runOrderCleanup(db, const SyncSettings(), now: now);
    expect((r.unpaidDeleted, r.sentDeleted), (0, 0));
    expect((await ids()).length, 6);
  });

  test('unpaid cleanup removes only old unpaid orders, with their lines', () async {
    final r = await runOrderCleanup(db, const SyncSettings(unpaidCleanup: true, cleanupDays: 15), now: now);
    expect(r.unpaidDeleted, 1);
    expect(await ids(), {'unpaid-new', 'pending-old', 'dead-old', 'sent-old', 'sent-new'});
    expect((await db.select(db.localOrderItems).get()).any((i) => i.orderId == 'unpaid-old'), false);
  });

  test('audit cleanup removes only orders the server already has, sent before the cut-off',
      () async {
    final r = await runOrderCleanup(db, const SyncSettings(auditCleanup: true, cleanupDays: 15), now: now);
    expect(r.sentDeleted, 1);
    expect(await ids(), {'unpaid-old', 'unpaid-new', 'pending-old', 'dead-old', 'sent-new'});
    expect((await db.select(db.localPayments).get()).any((p) => p.orderId == 'sent-old'), false);
  });

  test('a paid order waiting to be sent and a dead-lettered one are never deleted', () async {
    await runOrderCleanup(
        db, const SyncSettings(unpaidCleanup: true, auditCleanup: true, cleanupDays: 1), now: now);
    final left = await ids();
    expect(left.contains('pending-old'), true);
    expect(left.contains('dead-old'), true);
  });

  test('the days offset is clamped to 1..365 when read from the config', () {
    expect(SyncSettings.fromConfig({'offline_unpaid_cleanup_days_offset': '0'}).cleanupDays, 1);
    expect(SyncSettings.fromConfig({'offline_unpaid_cleanup_days_offset': '9999'}).cleanupDays, 365);
    expect(const SyncSettings().cleanupDays, 15);
    final s = SyncSettings.fromConfig({
      'offline_unpaid_cleanup_enabled': 'true',
      'offline_audit_cleanup': 'true',
    });
    expect((s.unpaidCleanup, s.auditCleanup), (true, true));
  });
}
