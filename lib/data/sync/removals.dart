import 'dart:async';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// One page of GET /api/sync/removals.
class RemovalsPage {
  /// (table, rowId): table is "barcodes", "product-images", "products" or
  /// "categories"; rowId is the id the device holds locally.
  final List<(String, int)> items;
  final bool last;
  final int nextAfterId;

  /// The server cleaned its list past our position (the device was offline
  /// longer than its limit): no items come back and every table must be
  /// pulled in full.
  final bool resetRequired;
  const RemovalsPage({
    required this.items,
    required this.last,
    required this.nextAfterId,
    this.resetRequired = false,
  });
}

/// Asks for one page. [afterId] is null only for the very first call, which
/// lists nothing and hands back the starting position.
typedef RemovalsFetcher = Future<RemovalsPage> Function({
  int? afterId,
  required int size,
  required Future<void> abort,
});

/// Rows the server deleted for good (offline.md "Removals"). A pull only ever
/// brings new and changed rows, so without this a replaced barcode or a
/// removed gallery image would stay on the device.
///
/// The position lives in the sync_state row named [feed]; the row existing
/// means the starting position was taken.
///  - First time ever: one call with no position (it lists nothing) and its
///    position is saved. This must happen before the first full pull of the
///    tables.
///  - Normal: send the saved position, delete the listed rows, and save the
///    new position in the SAME transaction as the deletions, so a dropped page
///    saves nothing. Repeat while more are coming.
///  - Reset required: the saved cursors of the pulled tables are cleared so
///    the next pull starts from the beginning (the data stays usable until
///    the new pull replaces it), and the new position is saved.
class Removals {
  Removals._();

  static const feed = 'removals';

  /// Returns how many local rows were deleted.
  static Future<int> apply(
    AppDatabase db,
    RemovalsFetcher fetch, {
    required Future<void> abort,
    Future<void> Function()? beforeEachPage,
    int pageSize = 200,
  }) async {
    final state = await (db.select(db.syncState)..where((t) => t.feed.equals(feed)))
        .getSingleOrNull();

    if (state == null) {
      final first = await fetch(afterId: null, size: pageSize, abort: abort);
      await _savePosition(db, first.nextAfterId);
      return 0;
    }

    var position = state.afterId;
    var removed = 0;
    while (true) {
      if (beforeEachPage != null) await beforeEachPage();
      final page = await fetch(afterId: position, size: pageSize, abort: abort);
      await db.transaction(() async {
        if (page.resetRequired) {
          await (db.update(db.syncState)..where((t) => t.feed.equals(feed).not()))
              .write(const SyncStateCompanion(
                  since: Value(null), afterId: Value(0)));
        } else {
          for (final (table, id) in page.items) {
            removed += await _delete(db, table, id);
          }
        }
        await _savePosition(db, page.nextAfterId);
      });
      position = page.nextAfterId;
      if (page.last || page.resetRequired) return removed;
    }
  }

  static Future<int> _delete(AppDatabase db, String table, int id) {
    switch (table) {
      case 'barcodes':
        return (db.delete(db.localBarcodes)..where((t) => t.id.equals(id))).go();
      case 'product-images':
        return (db.delete(db.localProductImages)..where((t) => t.id.equals(id))).go();
      // Deleting a product also lists its barcodes and gallery images, so
      // only the row itself goes here.
      case 'products':
        return (db.delete(db.localProducts)..where((t) => t.id.equals(id))).go();
      case 'categories':
        return (db.delete(db.localCategories)..where((t) => t.id.equals(id))).go();
      default:
        return Future.value(0); // a table this version does not hold
    }
  }

  static Future<void> _savePosition(AppDatabase db, int afterId) =>
      db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion(feed: const Value(feed), afterId: Value(afterId)),
          );
}
