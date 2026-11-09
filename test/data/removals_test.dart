import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/sync/feeds.dart';
import 'package:waha_kiosk/data/sync/removals.dart';
import 'package:waha_kiosk/data/sync/sync_engine.dart';

/// Rows the server deleted for good: removed here too. The position is saved
/// together with the deletions, so a dropped page changes nothing.
void main() {
  late AppDatabase db;
  late List<int?> asked;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    asked = [];
    await upsertPage(db, 'barcodes', [
      {'id': 1, 'productId': 10, 'barcode': 'A', 'primary': true, 'updatedAt': 'x'},
      {'id': 2, 'productId': 10, 'barcode': 'B', 'primary': false, 'updatedAt': 'x'},
      {'id': 3, 'productId': 11, 'barcode': 'C', 'primary': true, 'updatedAt': 'x'},
    ]);
    await upsertPage(db, 'product-images', [
      {'id': 5, 'productId': 10, 'resourceId': 99, 'sortOrder': 1, 'updatedAt': 'x'},
      {'id': 6, 'productId': 10, 'resourceId': 98, 'sortOrder': 2, 'updatedAt': 'x'},
    ]);
  });
  tearDown(() => db.close());

  Future<int> barcodes() async => (await db.select(db.localBarcodes).get()).length;
  Future<int> images() async => (await db.select(db.localProductImages).get()).length;
  Future<int?> position() async => (await (db.select(db.syncState)
            ..where((t) => t.feed.equals(Removals.feed)))
          .getSingleOrNull())
      ?.afterId;

  RemovalsFetcher serve(List<RemovalsPage> pages) {
    var i = 0;
    return ({afterId, required size, required abort}) async {
      asked.add(afterId);
      return pages[i++];
    };
  }

  Future<int> run(RemovalsFetcher f) =>
      Removals.apply(db, f, abort: Completer<void>().future);

  test('the first call has no position, lists nothing, and saves the starting position',
      () async {
    final n = await run(serve([
      const RemovalsPage(items: [], last: true, nextAfterId: 40),
    ]));
    expect(n, 0);
    expect(asked, [null]);
    expect(await position(), 40);
    expect(await barcodes(), 3); // nothing deleted
  });

  test('listed rows are deleted from the right table and the position moves on',
      () async {
    await run(serve([const RemovalsPage(items: [], last: true, nextAfterId: 40)]));
    asked.clear();
    final n = await run(serve([
      const RemovalsPage(
          items: [('barcodes', 2), ('product-images', 6)], last: true, nextAfterId: 43),
    ]));
    expect(n, 2);
    expect(asked, [40]); // sent the saved position
    expect(await barcodes(), 2);
    expect(await images(), 1);
    expect((await db.select(db.localBarcodes).get()).map((b) => b.id), [1, 3]);
    expect(await position(), 43);
  });

  test('several pages are read in one run; a row we do not hold or an unknown table is harmless',
      () async {
    await run(serve([const RemovalsPage(items: [], last: true, nextAfterId: 1)]));
    asked.clear();
    final n = await run(serve([
      const RemovalsPage(items: [('barcodes', 1)], last: false, nextAfterId: 2),
      const RemovalsPage(
          items: [('barcodes', 999), ('something-else', 3)], last: true, nextAfterId: 3),
    ]));
    expect(n, 1);
    expect(asked, [1, 2]);
    expect(await barcodes(), 2);
    expect(await position(), 3);
  });

  test('a dropped page changes nothing: the position stays and the rows stay',
      () async {
    await run(serve([const RemovalsPage(items: [], last: true, nextAfterId: 10)]));
    var call = 0;
    Future<RemovalsPage> flaky({int? afterId, required int size, required Future<void> abort}) async {
      call++;
      if (call == 1) {
        return const RemovalsPage(items: [('barcodes', 1)], last: false, nextAfterId: 11);
      }
      throw Exception('connection lost');
    }

    await expectLater(run(flaky), throwsException);
    expect(await position(), 11); // the first page was committed whole
    expect(await barcodes(), 2);
    // next run continues from the saved position
    asked.clear();
    await run(serve([const RemovalsPage(items: [('barcodes', 2)], last: true, nextAfterId: 12)]));
    expect(asked, [11]);
    expect(await barcodes(), 1);
  });

  test('a page that fails before it arrives saves nothing', () async {
    await run(serve([const RemovalsPage(items: [], last: true, nextAfterId: 10)]));
    await expectLater(
        run(({afterId, required size, required abort}) async => throw Exception('down')),
        throwsException);
    expect(await position(), 10);
    expect(await barcodes(), 3);
  });

  test('reset required: pull cursors are cleared so every table is pulled in full; data stays usable',
      () async {
    await run(serve([const RemovalsPage(items: [], last: true, nextAfterId: 10)]));
    await db.into(db.syncState).insertOnConflictUpdate(SyncStateCompanion(
        feed: const Value('products'),
        since: const Value('2026-11-08T10:00:00Z'),
        afterId: const Value(77),
        fullPullDone: const Value(true)));
    await run(serve([
      const RemovalsPage(items: [], last: true, nextAfterId: 500, resetRequired: true),
    ]));
    final products = await (db.select(db.syncState)
          ..where((t) => t.feed.equals('products')))
        .getSingle();
    expect(products.since, isNull);
    expect(products.afterId, 0);
    expect(products.fullPullDone, isTrue); // still usable until the new pull replaces it
    expect(await barcodes(), 3);
    expect(await position(), 500);
  });

  test('the removals position is not mistaken for a pulled table', () async {
    await run(serve([const RemovalsPage(items: [], last: true, nextAfterId: 10)]));
    final engine = SyncEngine(
        db: db, fetch: (f, {since, required afterId, required size, required abort}) =>
            throw UnimplementedError());
    expect(await engine.readyForOrders(), isFalse);
  });

  test('the customer coming back stops it before the next page', () async {
    await run(serve([const RemovalsPage(items: [], last: true, nextAfterId: 10)]));
    await expectLater(
        Removals.apply(
          db,
          serve([const RemovalsPage(items: [('barcodes', 1)], last: true, nextAfterId: 11)]),
          abort: Completer<void>().future,
          beforeEachPage: () async => throw StateError('customer active'),
        ),
        throwsStateError);
    expect(asked, [null]); // no second request was made
    expect(await barcodes(), 3);
  });
}
