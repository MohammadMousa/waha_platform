import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/sync/sync_engine.dart';

Map<String, dynamic> product(int id, String updatedAt,
        {bool active = true, String price = '5.00'}) =>
    {
      'id': id,
      'barcode': 'B$id',
      'sku': null,
      'name': {'ar': 'م$id', 'en': 'P$id'},
      'description': null,
      'price': price,
      'priceWithVat': '5.75',
      'active': active,
      'public': true,
      'categoryId': null,
      'imageResourceId': null,
      'updatedAt': updatedAt,
    };

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> productCount() async =>
      (await db.select(db.localProducts).get()).length;

  test('pages are saved with their cursor and the last page marks done',
      () async {
    final calls = <(String?, int)>[];
    final pages = [
      PullPage(
          items: [product(1, '2026-11-06T10:00:00Z'), product(2, '2026-11-06T10:00:01Z')],
          last: false,
          nextSince: '2026-11-06T10:00:01Z',
          nextAfterId: 2),
      PullPage(
          items: [product(3, '2026-11-06T10:00:02Z')],
          last: true,
          nextSince: '2026-11-06T10:00:02Z',
          nextAfterId: 3),
    ];
    var i = 0;
    final engine = SyncEngine(
      db: db,
      fetch: (feed, {since, required afterId, required size, required abort}) async {
        calls.add((since, afterId));
        return pages[i++];
      },
    );
    final n = await engine.pullFeed('products', abort: Completer<void>().future);
    expect(n, 3);
    expect(await productCount(), 3);
    expect(calls[0], (null, 0)); // first pull: no cursor
    expect(calls[1], ('2026-11-06T10:00:01Z', 2)); // exact cursor inside a run
    final st = await (db.select(db.syncState)..where((t) => t.feed.equals('products'))).getSingle();
    expect(st.since, '2026-11-06T10:00:02Z');
    expect(st.afterId, 3);
    expect(st.fullPullDone, true);
  });

  test('a failed page saves nothing and the next run resumes from the saved cursor',
      () async {
    var step = 0;
    final engine = SyncEngine(
      db: db,
      fetch: (feed, {since, required afterId, required size, required abort}) async {
        step++;
        if (step == 1) {
          return PullPage(
              items: [product(1, '2026-11-06T10:00:00Z')],
              last: false,
              nextSince: '2026-11-06T10:00:00Z',
              nextAfterId: 1);
        }
        throw const PullCancelled(); // customer touched the screen
      },
    );
    await expectLater(
        engine.pullFeed('products', abort: Completer<void>().future),
        throwsA(isA<PullCancelled>()));
    expect(await productCount(), 1); // page 1 stayed, page 2 never wrote
    final st = await (db.select(db.syncState)..where((t) => t.feed.equals('products'))).getSingle();
    expect(st.afterId, 1);
    expect(st.fullPullDone, false);

    // Next run: starts 10 s before the saved instant, from id 0.
    String? sentSince;
    int? sentAfter;
    final engine2 = SyncEngine(
      db: db,
      fetch: (feed, {since, required afterId, required size, required abort}) async {
        sentSince = since;
        sentAfter = afterId;
        return PullPage(
            items: [product(1, '2026-11-06T10:00:00Z')],
            last: true,
            nextSince: '2026-11-06T10:00:00Z',
            nextAfterId: 1);
      },
    );
    await engine2.pullFeed('products', abort: Completer<void>().future);
    expect(DateTime.parse(sentSince!).toUtc(),
        DateTime.utc(2026, 11, 6, 9, 59, 50));
    expect(sentAfter, 0);
    expect(await productCount(), 1); // overlap did not duplicate the row
  });

  test('a deactivated product arrives as inactive and updates in place',
      () async {
    PullPage one(Map<String, dynamic> p) => PullPage(
        items: [p], last: true, nextSince: p['updatedAt'] as String, nextAfterId: 1);
    var current = one(product(1, '2026-11-06T10:00:00Z'));
    final engine = SyncEngine(
      db: db,
      fetch: (feed, {since, required afterId, required size, required abort}) async => current,
    );
    await engine.pullFeed('products', abort: Completer<void>().future);
    current = one(product(1, '2026-11-06T11:00:00Z', active: false, price: '6.00'));
    await engine.pullFeed('products', abort: Completer<void>().future);
    final rows = await db.select(db.localProducts).get();
    expect(rows.length, 1);
    expect(rows.single.active, false);
    expect(rows.single.price, '6.00');
  });

  test('ready for orders only after products, barcodes and payment methods are done',
      () async {
    PullPage empty() => const PullPage(
        items: [], last: true, nextSince: '2026-11-06T10:00:00Z', nextAfterId: 0);
    final engine = SyncEngine(
      db: db,
      fetch: (feed, {since, required afterId, required size, required abort}) async => empty(),
    );
    expect(await engine.readyForOrders(), false);
    for (final f in ['products', 'barcodes']) {
      await engine.pullFeed(f, abort: Completer<void>().future);
    }
    expect(await engine.readyForOrders(), false);
    await engine.pullFeed('payment-methods', abort: Completer<void>().future);
    expect(await engine.readyForOrders(), true);
  });

  test('the count is rows new or changed, so a repeat pull of the same rows is 0',
      () async {
    // Rows the server sends again because they sit inside the 10 s overlap.
    List<Map<String, dynamic>> rows(String t2) => [
          product(1, '2026-11-06T10:00:00Z'),
          product(2, t2),
        ];
    var current = rows('2026-11-06T10:00:05Z');
    SyncEngine make() => SyncEngine(
          db: db,
          fetch: (feed, {since, required afterId, required size, required abort}) async =>
              PullPage(
                  items: current,
                  last: true,
                  nextSince: '2026-11-06T10:00:05Z',
                  nextAfterId: 2),
        );
    Future<int> pull() =>
        make().pullFeed('products', abort: Completer<void>().future);

    expect(await pull(), 2); // first pull: both are new
    expect(await pull(), 0); // the same rows again: nothing changed
    expect(await pull(), 0);
    current = rows('2026-11-06T10:00:09Z'); // one row really changed
    expect(await pull(), 1);
    current = [...rows('2026-11-06T10:00:09Z'), product(3, '2026-11-06T10:00:10Z')];
    expect(await pull(), 1); // one new row
    expect(await productCount(), 3);
  });
}
