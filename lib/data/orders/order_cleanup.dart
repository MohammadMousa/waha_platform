import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../sync/sync_settings.dart';

class CleanupResult {
  final int unpaidDeleted;
  final int sentDeleted;
  const CleanupResult(this.unpaidDeleted, this.sentDeleted);
}

/// Removes old local orders, only when the server's properties say so
/// (offline.md section 1). Two separate rules, both off by default:
/// - `offline_unpaid_cleanup_enabled`: orders that were never paid (so never
///   sent) and are older than the days offset;
/// - `offline_audit_cleanup`: orders the server already has (SYNCED) and that
///   were sent more than the days offset ago, with their lines and payments.
/// Paid orders still waiting to be sent, and dead-lettered ones, are NEVER
/// deleted here: they are the only copy.
Future<CleanupResult> runOrderCleanup(
  AppDatabase db,
  SyncSettings s, {
  DateTime? now,
}) async {
  final cutoff = (now ?? DateTime.now())
      .toUtc()
      .subtract(Duration(days: s.cleanupDays))
      .toIso8601String();
  var unpaid = 0;
  var sent = 0;

  Future<int> deleteOrders(List<String> ids) async {
    if (ids.isEmpty) return 0;
    await (db.delete(db.localOrderItems)..where((t) => t.orderId.isIn(ids))).go();
    await (db.delete(db.localPayments)..where((t) => t.orderId.isIn(ids))).go();
    return (db.delete(db.localOrders)..where((t) => t.orderId.isIn(ids))).go();
  }

  await db.transaction(() async {
    if (s.unpaidCleanup) {
      final rows = await (db.select(db.localOrders)
            ..where((t) =>
                t.syncState.equals('LOCAL') &
                t.status.equals('CREATED') &
                t.createdAt.isSmallerThanValue(cutoff)))
          .get();
      unpaid = await deleteOrders([for (final r in rows) r.orderId]);
    }
    if (s.auditCleanup) {
      final rows = await (db.select(db.localOrders)
            ..where((t) =>
                t.syncState.equals('SYNCED') &
                t.syncedAt.isNotNull() &
                t.syncedAt.isSmallerThanValue(cutoff)))
          .get();
      sent = await deleteOrders([for (final r in rows) r.orderId]);
    }
  });
  return CleanupResult(unpaid, sent);
}
