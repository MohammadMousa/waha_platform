import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/sync/feeds.dart';
import 'package:waha_kiosk/data/sync/pull_combined.dart';
import 'package:waha_kiosk/data/sync/removals.dart';
import 'package:waha_kiosk/data/sync/sync_engine.dart';
import 'package:waha_kiosk/data/sync/table_freshness.dart';

Map<String, dynamic> product(int id, String at) => {
      'id': id,
      'barcode': 'B$id',
      'sku': null,
      'name': {'ar': 'م$id', 'en': 'P$id'},
      'description': null,
      'price': '5.00',
      'priceWithVat': '5.75',
      'active': true,
      'public': true,
      'categoryId': null,
      'imageResourceId': null,
      'updatedAt': at,
    };

Map<String, dynamic> done(String since, int id, [List<Map<String, dynamic>> items = const []]) =>
    {'items': items, 'last': true, 'next': {'since': since, 'afterId': id}};

Map<String, dynamic> answer({
  String time = '2026-11-25T09:00:00Z',
  Map<String, dynamic>? removals,
  Map<String, dynamic>? tables,
  Map<String, dynamic>? config,
}) =>
    {
      'serverTime': time,
      'deviceConfig': {'deviceId': 'd1'},
      if (config != null) 'tableConfig': config,
      'removals': removals ?? {'items': [], 'last': true, 'next': {'afterId': 5}, 'resetRequired': false},
      'tables': tables ?? {for (final f in kSyncFeeds) f: done('2026-11-25T08:00:00Z', 1)},
    };

void main() {
  late AppDatabase db;
  late TableFreshness fresh;
  late List<Map<String, dynamic>> requests;
  late List<Map<String, dynamic>> deviceConfigs;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    fresh = TableFreshness(persist: (_, __) {}, stopwatch: Stopwatch());
    requests = [];
    deviceConfigs = [];
  });
  tearDown(() => db.close());

  CombinedPuller puller(List<Object> script) {
    var i = 0;
    return CombinedPuller(
      db: db,
      freshness: fresh,
      onDeviceConfig: (c) async => deviceConfigs.add(c),
      fetch: (body, abort) async {
        requests.add(body);
        final s = script[i++];
        if (s is Exception) throw s;
        return CombinedAnswer.parse(s as Map<String, dynamic>);
      },
    );
  }

  Future<CombinedResult> run(CombinedPuller p, {bool manual = false}) =>
      p.run(manual: manual, abort: Completer<void>().future);

  Future<SyncStateData?> state(String f) =>
      (db.select(db.syncState)..where((t) => t.feed.equals(f))).getSingleOrNull();

  test('nothing new is exactly one request; the device settings and the starting position are saved', () async {
    final r = await run(puller([answer()]));
    expect(r.calls, 1);
    expect(requests, hasLength(1));
    expect(requests[0]['force'], false);
    expect((requests[0]['tables'] as Map).keys, kSyncFeeds); // first pull: every table, no cursor
    expect((requests[0]['tables'] as Map).values.every((v) => v == null), true);
    expect(requests[0].containsKey('removalsAfterId'), false);
    expect(deviceConfigs.single['deviceId'], 'd1');
    expect(await Removals.savedPosition(db), 5);
    expect((await state('products'))!.fullPullDone, true);
    expect(fresh.checkedAt.keys, containsAll([...kSyncFeeds, 'removals']));
  });

  test('a big first sync loops; finished tables are left out of later calls', () async {
    final first = answer(tables: {
      'products': {
        'items': [product(1, '2026-11-25T08:00:01Z'), product(2, '2026-11-25T08:00:02Z')],
        'last': false,
        'next': {'since': '2026-11-25T08:00:02Z', 'afterId': 2},
      },
      'barcodes': done('2026-11-25T08:00:00Z', 0),
      'categories': {'items': [], 'last': false, 'deferred': true, 'next': {'since': null, 'afterId': 0}},
      'payment-methods': done('2026-11-25T08:00:00Z', 1),
      'store-payment-methods': done('2026-11-25T08:00:00Z', 1),
      'product-images': done('2026-11-25T08:00:00Z', 1),
    });
    final second = answer(tables: {
      'products': {
        'items': [product(3, '2026-11-25T08:00:03Z')],
        'last': true,
        'next': {'since': '2026-11-25T08:00:03Z', 'afterId': 3},
      },
      'categories': done('2026-11-25T08:00:00Z', 1),
    });
    final r = await run(puller([first, second]));
    expect(r.calls, 2);
    expect(r.rows, 3);
    expect((requests[1]['tables'] as Map).keys, ['products', 'categories']);
    // the cursor inside the run is exactly what the server returned
    expect(requests[1]['tables']['products'], {'since': '2026-11-25T08:00:02Z', 'afterId': 2});
    // removals finished in the first call: later calls of the same pull leave them out
    expect(requests[1].containsKey('removalsAfterId'), false);
    expect((await state('products'))!.fullPullDone, true);
    expect((await db.select(db.localProducts).get()).length, 3);
  });

  test('a deferred table saves no cursor', () async {
    final a = answer(tables: {
      for (final f in kSyncFeeds)
        f: f == 'barcodes'
            ? {'items': [], 'last': false, 'deferred': true, 'next': {'since': null, 'afterId': 0}}
            : done('2026-11-25T08:00:00Z', 1),
    });
    final b = answer(tables: {'barcodes': done('2026-11-25T08:00:00Z', 1)});
    await run(puller([a, b]));
    expect(requests[1]['tables']['barcodes'], isNull); // still no cursor to send
  });

  test('the first request of a table starts 10 s before the saved cursor', () async {
    await SyncEngine.savePage(
        db,
        'products',
        PullPage(items: [product(1, '2026-11-25T08:00:00Z')], last: true, nextSince: '2026-11-25T08:00:00Z', nextAfterId: 1));
    await run(puller([answer()]));
    expect(requests[0]['tables']['products'], {'since': '2026-11-25T07:59:50.000Z', 'afterId': 0});
  });

  test('removals are applied before the tables, and the position moves', () async {
    await upsertPage(db, 'barcodes', [
      {'id': 1, 'productId': 10, 'barcode': 'A', 'primary': true, 'updatedAt': 'x'},
    ]);
    await Removals.saveStartingPosition(db, 3);
    final a = answer(removals: {
      'items': [
        {'table': 'barcodes', 'rowId': 1}
      ],
      'last': true,
      'next': {'afterId': 9},
      'resetRequired': false,
    });
    final r = await run(puller([a]));
    expect(r.removed, 1);
    expect(requests[0]['removalsAfterId'], 3);
    expect(await Removals.savedPosition(db), 9);
    expect((await db.select(db.localBarcodes).get()), isEmpty);
  });

  test('reset required: the tables of that answer are dropped and everything starts again', () async {
    await SyncEngine.savePage(
        db,
        'products',
        PullPage(items: [product(1, '2026-11-25T08:00:00Z')], last: true, nextSince: '2026-11-25T08:00:00Z', nextAfterId: 1));
    await Removals.saveStartingPosition(db, 3);
    final reset = answer(
      removals: {'items': [], 'last': true, 'next': {'afterId': 20}, 'resetRequired': true},
      tables: {
        'products': {
          'items': [product(99, '2026-11-25T08:00:09Z')],
          'last': true,
          'next': {'since': '2026-11-25T08:00:09Z', 'afterId': 99},
        },
      },
    );
    final again = answer(removals: {'items': [], 'last': true, 'next': {'afterId': 20}, 'resetRequired': false});
    final r = await run(puller([reset, again]));
    expect(r.calls, 2);
    final ids = (await db.select(db.localProducts).get()).map((p) => p.id).toList();
    expect(ids, [1]); // 99 from the reset answer was never saved
    expect(requests[1]['tables']['products'], isNull); // from the start
    expect(requests[1]['removalsAfterId'], 20);
  });

  test('skipped (disabled or fresh) counts as complete and is no error', () async {
    final a = answer(tables: {
      'products': done('2026-11-25T08:00:00Z', 1),
      'barcodes': done('2026-11-25T08:00:00Z', 1),
      'categories': {'skipped': 'disabled'},
      'payment-methods': done('2026-11-25T08:00:00Z', 1),
      'store-payment-methods': {'skipped': 'fresh'},
      'product-images': {'skipped': 'unknown'},
    });
    final r = await run(puller([a]));
    expect(r.calls, 1);
    expect(await state('categories'), isNull); // not pulled, nothing recorded
    expect(await state('store-payment-methods'), isNull);
    expect(fresh.checkedAt.containsKey('categories'), false);
  });

  test('removals switched off: the starting position is taken only when none is saved', () async {
    final off = {'skipped': 'disabled', 'next': {'afterId': 42}};
    await run(puller([answer(removals: off)]));
    expect(await Removals.savedPosition(db), 42);
    await run(puller([answer(removals: {'skipped': 'disabled', 'next': {'afterId': 77}})]));
    expect(await Removals.savedPosition(db), 42); // never moved while off
  });

  // Removals inside their period (12 hours), checked a moment ago.
  void removalsRecentlyChecked({bool active = true}) {
    fresh.onAnswer(
        serverTime: '2026-11-25T09:00:00Z',
        config: {'removals': TableRule(active: active, ttlSeconds: 43200)});
    fresh.markChecked('removals', '2026-11-25T09:00:00Z');
  }

  test('removals inside their period are left out, and an answer for them is ignored', () async {
    await Removals.saveStartingPosition(db, 8);
    removalsRecentlyChecked();
    // a server that still hands out its newest position must not move ours
    final r = await run(puller([answer(removals: {'items': [], 'last': true, 'next': {'afterId': 99}, 'resetRequired': false})]));
    expect(requests[0].containsKey('removalsAfterId'), false);
    expect(requests[0].containsKey('removalsCheckedAt'), false);
    expect(await Removals.savedPosition(db), 8);
    expect(r.removalsChecked, false);
    expect(r.calls, 1);
  });

  test('removals with no saved position are always asked for (the starting position)', () async {
    removalsRecentlyChecked();
    await run(puller([answer()]));
    expect(requests[0].containsKey('removalsAfterId'), false); // none to send
    expect(await Removals.savedPosition(db), 5); // taken from the answer
  });

  test('a manual pull asks for removals even inside their period', () async {
    await Removals.saveStartingPosition(db, 8);
    removalsRecentlyChecked();
    await run(puller([answer()]), manual: true);
    expect(requests[0]['removalsAfterId'], 8);
  });

  test('removals switched off with a saved position are left out', () async {
    await Removals.saveStartingPosition(db, 8);
    removalsRecentlyChecked(active: false);
    await run(puller([answer()]));
    expect(requests[0].containsKey('removalsAfterId'), false);
    expect(await Removals.savedPosition(db), 8);
  });

  test('removals past their period are asked for again', () async {
    await Removals.saveStartingPosition(db, 8);
    fresh.onAnswer(
        serverTime: '2026-11-25T09:00:00Z',
        config: {'removals': const TableRule(active: true, ttlSeconds: 43200)});
    fresh.markChecked('removals', '2026-11-24T08:00:00Z'); // 25 hours ago
    await run(puller([answer()]));
    expect(requests[0]['removalsAfterId'], 8);
  });

  test('only a real removals check counts as checked', () async {
    await Removals.saveStartingPosition(db, 8);
    final fresh1 = await run(puller([answer(removals: {'skipped': 'fresh'})]));
    expect(fresh1.removalsChecked, false);
    final off1 = await run(puller([answer(removals: {'skipped': 'disabled', 'next': {'afterId': 9}})]));
    expect(off1.removalsChecked, false);
    final real = await run(puller([answer()]));
    expect(real.removalsChecked, true);
  });

  test('the call log names removals as asked, and as left out when the server says fresh', () async {
    await Removals.saveStartingPosition(db, 8);
    final lines = <String>[];
    final p = CombinedPuller(
      db: db,
      freshness: fresh,
      onDeviceConfig: (c) async {},
      onCall: (n, asked, skipped, rows) => lines.add('${asked.contains('removals')}|${skipped.contains('removals')}'),
      fetch: (body, abort) async =>
          CombinedAnswer.parse(answer(removals: {'skipped': 'fresh'})),
    );
    await run(p);
    expect(lines, ['true|true']);
  });

  test('removals fresh: the position stays, no error', () async {
    await Removals.saveStartingPosition(db, 8);
    await run(puller([answer(removals: {'skipped': 'fresh'})]));
    expect(await Removals.savedPosition(db), 8);
  });

  test('a manual pull sends force and asks for every table even inside the period', () async {
    fresh.onAnswer(serverTime: '2026-11-25T09:00:00Z', config: {
      for (final f in kSyncFeeds) f: const TableRule(active: true, ttlSeconds: 86400),
    });
    for (final f in kSyncFeeds) {
      fresh.markChecked(f, '2026-11-25T08:59:00Z');
    }
    await run(puller([answer()]), manual: true);
    expect(requests[0]['force'], true);
    expect((requests[0]['tables'] as Map).keys, kSyncFeeds);
  });

  test('a scheduled pull leaves out fresh and switched-off tables before sending', () async {
    fresh.onAnswer(serverTime: '2026-11-25T09:00:00Z', config: {
      'products': const TableRule(active: true, ttlSeconds: 86400),
      'categories': const TableRule(active: false, ttlSeconds: 0),
    });
    fresh.markChecked('products', '2026-11-25T08:59:00Z');
    final r = await run(puller([answer(tables: {
      'barcodes': done('2026-11-25T08:00:00Z', 1),
      'payment-methods': done('2026-11-25T08:00:00Z', 1),
      'store-payment-methods': done('2026-11-25T08:00:00Z', 1),
      'product-images': done('2026-11-25T08:00:00Z', 1),
    })]));
    expect(r.calls, 1);
    expect((requests[0]['tables'] as Map).keys,
        ['barcodes', 'payment-methods', 'store-payment-methods', 'product-images']);
  });

  test('table settings from the answer are saved for the next pull', () async {
    await run(puller([
      answer(config: {
        'products': {'active': true, 'ttlSeconds': 10800},
        'categories': {'active': false, 'ttlSeconds': 0},
      })
    ]));
    expect(fresh.rule('products')!.ttlSeconds, 10800);
    expect(fresh.rule('categories')!.active, false);
  });

  test('a lost answer saves nothing; the next run resumes from what was saved', () async {
    final first = answer(tables: {
      'products': {
        'items': [product(1, '2026-11-25T08:00:01Z')],
        'last': false,
        'next': {'since': '2026-11-25T08:00:01Z', 'afterId': 1},
      },
    });
    final p = puller([first, Exception('connection lost')]);
    await expectLater(run(p), throwsA(isA<Exception>()));
    expect((await state('products'))!.afterId, 1);
    expect((await state('products'))!.fullPullDone, false);
    expect(p.unfinished, contains('products'));
    expect((await db.select(db.localProducts).get()).length, 1);
  });

  test('the server making no progress ends the pull instead of looping', () async {
    final stuck = answer(tables: {
      'products': {'items': [], 'last': false, 'deferred': true, 'next': {'since': null, 'afterId': 0}},
    });
    final p = puller([stuck, stuck]);
    await expectLater(run(p), throwsA(isA<StateError>()));
    expect(requests, hasLength(2)); // the first call moved the removals position; the second moved nothing
    expect(p.unfinished, contains('products'));
  });

  test('a customer coming back stops it before the next call', () async {
    final a = answer(tables: {
      'products': {
        'items': [product(1, '2026-11-25T08:00:01Z')],
        'last': false,
        'next': {'since': '2026-11-25T08:00:01Z', 'afterId': 1},
      },
    });
    var calls = 0;
    final p = puller([a, answer()]);
    await expectLater(
        p.run(
          manual: false,
          abort: Completer<void>().future,
          beforeEachCall: () async {
            if (++calls == 2) throw const PullCancelled();
          },
        ),
        throwsA(isA<PullCancelled>()));
    expect(requests, hasLength(1));
  });

  test('a 404 is passed up so the caller can use the per-table way', () async {
    final p = puller([const CombinedNotSupported()]);
    await expectLater(run(p), throwsA(isA<CombinedNotSupported>()));
    expect(await state('products'), isNull);
  });
}
