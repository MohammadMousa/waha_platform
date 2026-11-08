import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/resources/resource_cache.dart';
import 'package:waha_kiosk/data/resources/resource_settings.dart';

/// The lazy resource cache against a fake server that behaves like the real
/// one: an ETag on every resource, and 304 only when If-None-Match is EXACTLY
/// the current ETag.
class FakeServer {
  late HttpServer server;
  final Map<String, List<int>> content = {};
  final Map<String, String> types = {};
  final List<String> requests = []; // "GET /path (if-none-match)"
  final List<Map<String, String>> sentHeaders = [];
  int forceStatus = 0; // 0 = normal
  Duration delay = Duration.zero;

  String etagOf(List<int> b) => '"${sha256.convert(b)}"';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final inm = req.headers.value('if-none-match');
      requests.add('${req.method} ${req.uri.path}${inm != null ? ' [$inm]' : ''}');
      sentHeaders.add({
        for (final e in {'authorization': req.headers.value('authorization')}.entries)
          if (e.value != null) e.key: e.value!
      });
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final r = req.response;
      if (forceStatus != 0) {
        r.statusCode = forceStatus;
        r.headers.contentType = ContentType.json;
        r.write('{"error":"x"}');
        await r.close();
        return;
      }
      final body = content[req.uri.path];
      if (body == null) {
        r.statusCode = 404;
        r.headers.contentType = ContentType.json;
        r.write('{"error":"not found"}');
        await r.close();
        return;
      }
      final tag = etagOf(body);
      r.headers.set('etag', tag);
      if (inm == tag) {
        r.statusCode = 304;
        await r.close();
        return;
      }
      r.headers.set('content-type', types[req.uri.path] ?? 'image/png');
      r.add(body);
      await r.close();
    });
  }

  String get base => 'http://127.0.0.1:${server.port}';
  Future<void> stop() => server.close(force: true);
}

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase db;
  late Directory dir;
  late FakeServer srv;
  late ResourceCache cache;
  late DateTime clock;
  var reachable = true;
  var recheck = 10;

  final img1 = utf8.encode('image-bytes-one');
  final img2 = utf8.encode('image-bytes-two');
  const idAddr = '/api/resources/125';
  const pathAddr = '/resource/waha/pages/logo.png';

  int filesInDir() => dir.listSync().whereType<File>().length;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('rescache');
    srv = FakeServer();
    await srv.start();
    clock = DateTime.utc(2026, 11, 8, 10);
    reachable = true;
    recheck = 10;
    cache = ResourceCache(
      db: db,
      dir: dir,
      baseUrl: () => srv.base,
      headers: () => {'Authorization': 'Bearer tok'},
      canReach: () => reachable,
      now: () => clock,
      settings: () => ResourceSettings(recheckMinutes: recheck),
    );
    srv.content[idAddr] = img1;
    srv.content[pathAddr] = img1;
  });
  tearDown(() async {
    cache.dispose();
    await srv.stop();
    await db.close();
    await dir.delete(recursive: true);
  });

  test('first view downloads and saves it by hash; the next view needs no request',
      () async {
    final r = await cache.get(idAddr);
    expect(r, isNotNull);
    expect(await r!.file.readAsBytes(), img1);
    expect(r.mimeType, 'image/png');
    expect(r.file.path.endsWith(sha256.convert(img1).toString()), isTrue);
    final row = await db.select(db.cachedResources).getSingle();
    expect(row.address, idAddr);
    expect(row.etag, srv.etagOf(img1));
    expect(row.sizeBytes, img1.length);
    expect(srv.sentHeaders.first['authorization'], 'Bearer tok');
    srv.requests.clear();
    expect(await cache.get(idAddr), isNotNull);
    expect(srv.requests, isEmpty);
  });

  test('a by-id address is never revalidated, however old', () async {
    await cache.get(idAddr);
    srv.requests.clear();
    clock = clock.add(const Duration(days: 20));
    await cache.get(idAddr);
    await cache.whenIdle();
    expect(srv.requests, isEmpty);
  });

  test('a path address: checked with the saved ETag verbatim, at most once per recheck time',
      () async {
    await cache.get(pathAddr);
    srv.requests.clear();
    clock = clock.add(const Duration(minutes: 5)); // too soon
    await cache.get(pathAddr);
    await cache.whenIdle();
    expect(srv.requests, isEmpty);

    clock = clock.add(const Duration(minutes: 6)); // due
    final changes = <String>[];
    cache.changes.listen(changes.add);
    final r = await cache.get(pathAddr);
    expect(await r!.file.readAsBytes(), img1); // the saved copy answers at once
    await cache.whenIdle();
    expect(srv.requests.single, 'GET $pathAddr [${srv.etagOf(img1)}]'); // exact, with quotes
    expect(changes, isEmpty); // 304: nothing changed
    // and the throttle restarted
    srv.requests.clear();
    await cache.get(pathAddr);
    await cache.whenIdle();
    expect(srv.requests, isEmpty);
  });

  test('a changed path resource: old copy first, then replaced and announced; old bytes removed',
      () async {
    await cache.get(pathAddr);
    srv.content[pathAddr] = img2;
    clock = clock.add(const Duration(minutes: 11));
    final changes = <String>[];
    cache.changes.listen(changes.add);
    final first = await cache.get(pathAddr);
    expect(await first!.file.readAsBytes(), img1); // still the old one
    await cache.whenIdle();
    await Future<void>.delayed(Duration.zero);
    expect(changes, [pathAddr]);
    final next = await cache.get(pathAddr);
    expect(await next!.file.readAsBytes(), img2);
    expect(filesInDir(), 1); // the old bytes are gone
    final row = await db.select(db.cachedResources).getSingle();
    expect(row.etag, srv.etagOf(img2));
  });

  test('a failed check keeps the saved copy and is not repeated until the recheck time',
      () async {
    await cache.get(pathAddr);
    clock = clock.add(const Duration(minutes: 11));
    srv.forceStatus = 500;
    srv.requests.clear();
    expect(await (await cache.get(pathAddr))!.file.readAsBytes(), img1);
    await cache.whenIdle();
    expect(srv.requests.length, 1);
    await cache.get(pathAddr); // same moment: no hammering
    await cache.whenIdle();
    expect(srv.requests.length, 1);
    expect(await (await cache.get(pathAddr))!.file.readAsBytes(), img1);
    // later it tries again and succeeds
    srv.forceStatus = 0;
    clock = clock.add(const Duration(minutes: 11));
    await cache.get(pathAddr);
    await cache.whenIdle();
    expect(srv.requests.length, 2);
  });

  test('the server no longer has it (404): the saved copy is deleted and announced',
      () async {
    await cache.get(pathAddr);
    srv.content.remove(pathAddr);
    clock = clock.add(const Duration(minutes: 11));
    final changes = <String>[];
    cache.changes.listen(changes.add);
    await cache.get(pathAddr);
    await cache.whenIdle();
    await Future<void>.delayed(Duration.zero);
    expect(changes, [pathAddr]);
    expect(await db.select(db.cachedResources).get(), isEmpty);
    expect(filesInDir(), 0);
    expect(await cache.get(pathAddr), isNull); // and it is not served any more
  });

  test('errors are never saved: 404, 401 and 500 on the first fetch', () async {
    for (final s in [404, 401, 500]) {
      srv.forceStatus = s;
      expect(await cache.get(idAddr), isNull, reason: '$s');
    }
    expect(await db.select(db.cachedResources).get(), isEmpty);
    expect(filesInDir(), 0);
  });

  test('logs are never cached and never requested', () async {
    srv.content['/api/logs/7'] = utf8.encode('log text');
    expect(await cache.get('/api/logs/7'), isNull);
    expect(srv.requests, isEmpty);
    expect(await db.select(db.cachedResources).get(), isEmpty);
  });

  test('the same bytes at two addresses are stored once, and kept while one still uses them',
      () async {
    srv.content['/resource/waha/pages/copy.png'] = img1;
    await cache.get(pathAddr);
    await cache.get('/resource/waha/pages/copy.png');
    expect(filesInDir(), 1);
    expect((await db.select(db.cachedResources).get()).length, 2);
    // one address changes: the shared bytes stay for the other
    srv.content[pathAddr] = img2;
    clock = clock.add(const Duration(minutes: 11));
    await cache.get(pathAddr);
    await cache.whenIdle();
    expect(filesInDir(), 2);
    expect(await (await cache.get('/resource/waha/pages/copy.png'))!.file.readAsBytes(), img1);
  });

  test('offline: the saved copy is served with no request; an unsaved one is null',
      () async {
    await cache.get(pathAddr);
    reachable = false;
    srv.requests.clear();
    clock = clock.add(const Duration(days: 2));
    expect(await (await cache.get(pathAddr))!.file.readAsBytes(), img1);
    await cache.whenIdle();
    expect(await cache.get(idAddr), isNull);
    expect(srv.requests, isEmpty);
  });

  test('server down on first fetch: null, nothing saved', () async {
    await srv.stop();
    expect(await cache.get(idAddr), isNull);
    expect(await db.select(db.cachedResources).get(), isEmpty);
    srv = FakeServer();
    await srv.start(); // so tearDown has something to stop
  });

  test('two screens asking at once cause one download', () async {
    srv.delay = const Duration(milliseconds: 100);
    final both = await Future.wait([cache.get(idAddr), cache.get(idAddr)]);
    expect(both.every((r) => r != null), isTrue);
    expect(srv.requests.length, 1);
  });

  test('a file that is too big is not saved', () async {
    final small = ResourceCache(
      db: db, dir: dir, baseUrl: () => srv.base, now: () => clock, maxFileBytes: 4);
    expect(await small.get(idAddr), isNull);
    expect(await db.select(db.cachedResources).get(), isEmpty);
    small.dispose();
  });

  test('a row whose file is gone is fetched again', () async {
    final r = await cache.get(idAddr);
    await r!.file.delete();
    srv.requests.clear();
    final again = await cache.get(idAddr);
    expect(await again!.file.readAsBytes(), img1);
    expect(srv.requests.length, 1);
  });

  test('last shown is updated, but not on every redraw', () async {
    await cache.get(idAddr);
    Future<String> lastUsed() async =>
        (await db.select(db.cachedResources).getSingle()).lastUsedAt;
    final t0 = await lastUsed();
    clock = clock.add(const Duration(seconds: 20));
    await cache.get(idAddr);
    expect(await lastUsed(), t0); // within a minute: not written
    clock = clock.add(const Duration(minutes: 2));
    await cache.get(idAddr);
    expect(await lastUsed(), isNot(t0));
  });

  test('settings come from the config with defaults and limits', () {
    final d = ResourceSettings.fromConfig({});
    expect((d.maxMb, d.maxAgeDays, d.recheckMinutes), (200, 30, 10));
    final c = ResourceSettings.fromConfig({
      'resource_cache_max_mb': '50',
      'resource_cache_max_age_days': '7',
      'resource_cache_recheck_minutes': '2',
    });
    expect((c.maxMb, c.maxAgeDays, c.recheckMinutes), (50, 7, 2));
    final bad = ResourceSettings.fromConfig({
      'resource_cache_max_mb': 'x',
      'resource_cache_max_age_days': '0',
      'resource_cache_recheck_minutes': '99999',
    });
    expect((bad.maxMb, bad.maxAgeDays, bad.recheckMinutes), (200, 1, 1440));
    final big = ResourceSettings.fromConfig({
      'resource_cache_max_mb': '999999',
      'resource_cache_max_age_days': '9999',
    });
    expect((big.maxMb, big.maxAgeDays), (10240, 365)); // the backend's ranges
  });

  group('cleanup', () {
    ResourceCache make({
      int maxMb = 200,
      int maxAgeDays = 30,
      Set<String> pinned = const {},
      bool Function()? isIdle,
      Duration delay = const Duration(hours: 1), // the automatic run stays out of the way
    }) =>
        ResourceCache(
          db: db,
          dir: dir,
          baseUrl: () => srv.base,
          canReach: () => reachable,
          now: () => clock,
          settings: () => ResourceSettings(maxMb: maxMb, maxAgeDays: maxAgeDays),
          pinned: () async => pinned,
          isIdle: isIdle,
        )..cleanupDelay = delay;

    Future<Set<String>> saved() async =>
        {for (final r in await db.select(db.cachedResources).get()) r.address};

    List<int> big(int seed) => List<int>.filled(600 * 1024, seed);

    test('not shown for too long is removed; shown regularly never expires',
        () async {
      final c = make();
      for (final n in ['a', 'b', 'c']) {
        srv.content['/api/resources/$n'] = utf8.encode('bytes-$n');
      }
      // saved the same day
      for (final n in ['a', 'b', 'c']) {
        await c.get('/api/resources/$n');
      }
      clock = clock.add(const Duration(days: 20));
      await c.get('/api/resources/a'); // a is shown again, b and c are not
      clock = clock.add(const Duration(days: 15)); // a: 15 days ago, b and c: 35
      final removed = await c.cleanup();
      expect(removed, 2);
      expect(await saved(), {'/api/resources/a'});
      expect(filesInDir(), 1);
      c.dispose();
    });

    test('over the size cap: the least recently shown go first, down to about 90%',
        () async {
      final c = make(maxMb: 1);
      for (var i = 1; i <= 3; i++) {
        srv.content['/api/resources/$i'] = big(i);
        await c.get('/api/resources/$i');
        clock = clock.add(const Duration(minutes: 5));
      }
      // 3 x 600 KB = 1.8 MB over 1 MB: the oldest two go (down to 600 KB)
      expect(await c.cleanup(), 2);
      expect(await saved(), {'/api/resources/3'});
      expect(filesInDir(), 1);
      c.dispose();
    });

    test('the landing page and its files are never removed', () async {
      final c = make(maxMb: 1, pinned: {'/api/resources/1'});
      for (var i = 1; i <= 3; i++) {
        srv.content['/api/resources/$i'] = big(i);
        await c.get('/api/resources/$i');
        clock = clock.add(const Duration(minutes: 5));
      }
      clock = clock.add(const Duration(days: 60)); // everything is also too old
      await c.cleanup();
      expect(await saved(), {'/api/resources/1'});
      c.dispose();
    });

    test('nothing is removed while the server cannot be reached', () async {
      final c = make(maxAgeDays: 1);
      await c.get(idAddr);
      clock = clock.add(const Duration(days: 40));
      reachable = false;
      expect(await c.cleanup(), 0);
      expect(await saved(), {idAddr});
      reachable = true;
      expect(await c.cleanup(), 1);
      c.dispose();
    });

    test('bytes used by two addresses stay while one of them is kept', () async {
      final c = make();
      srv.content['/api/resources/x'] = img1;
      srv.content['/api/resources/y'] = img1;
      await c.get('/api/resources/x');
      clock = clock.add(const Duration(days: 25));
      await c.get('/api/resources/y'); // y is recent, x is not
      clock = clock.add(const Duration(days: 10));
      await c.cleanup();
      expect(await saved(), {'/api/resources/y'});
      expect(filesInDir(), 1); // the shared file is still there
      expect(await (await c.get('/api/resources/y'))!.file.readAsBytes(), img1);
      c.dispose();
    });

    test('files nothing points to are removed; a download in progress is left', () async {
      final c = make();
      await c.get(idAddr);
      File('${dir.path}/deadbeef').writeAsBytesSync([1]);
      final oldTmp = File('${dir.path}/tmp-old')..writeAsBytesSync([1]);
      oldTmp.setLastModifiedSync(DateTime.utc(2020));
      final newTmp = File('${dir.path}/tmp-new')..writeAsBytesSync([1]);
      newTmp.setLastModifiedSync(clock);
      await c.cleanup();
      expect(File('${dir.path}/deadbeef').existsSync(), isFalse);
      expect(oldTmp.existsSync(), isFalse);
      expect(newTmp.existsSync(), isTrue);
      expect(await saved(), {idAddr});
      c.dispose();
    });

    test('it runs by itself after a save, but only when the screen is idle',
        () async {
      var idle = false;
      final c = make(
          maxAgeDays: 1, isIdle: () => idle, delay: const Duration(milliseconds: 30));
      srv.content['/api/resources/old'] = utf8.encode('old');
      srv.content['/api/resources/new'] = utf8.encode('new');
      await c.get('/api/resources/old');
      clock = clock.add(const Duration(days: 5));
      await c.get('/api/resources/new'); // a save: cleanup is scheduled
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await saved(), {'/api/resources/old', '/api/resources/new'}); // busy screen
      idle = true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await saved(), {'/api/resources/new'});
      c.dispose();
    });
  });
}
