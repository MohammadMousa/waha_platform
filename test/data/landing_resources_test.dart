import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/resources/html_assets.dart';
import 'package:waha_kiosk/data/resources/resource_cache.dart';
import 'package:waha_kiosk/data/resources/resource_cache_holder.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/landing_cache.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

/// The landing page and the files it uses are resources like any other.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase db;
  late Directory dir;
  late HttpServer server;
  late ResourceCache cache;
  late String base;
  final files = <String, List<int>>{};
  final types = <String, String>{};
  final requests = <String>[];
  var status = 200;

  // 4 bytes that start like a JPEG.
  final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];
  const page = '/resource/waha_corp/oasis/pages/KIOSK_LANDING.html';
  const img = '/resource/waha_corp/oasis/resources/photo.jpeg';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('landing');
    files.clear();
    types.clear();
    requests.clear();
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req.uri.path);
      final body = files[req.uri.path];
      if (status != 200 || body == null) {
        req.response.statusCode = status != 200 ? status : 404;
      } else {
        req.response.headers.set('etag', '"t-${body.length}"');
        req.response.headers.set(
            'content-type', types[req.uri.path] ?? 'application/octet-stream');
        req.response.add(body);
      }
      await req.response.close();
    });
    base = 'http://127.0.0.1:${server.port}';
    cache = ResourceCache(db: db, dir: dir, baseUrl: () => base);
    ResourceCacheHolder.instance = cache;
  });
  tearDown(() async {
    ResourceCacheHolder.instance = null;
    cache.dispose();
    await server.close(force: true);
    await db.close();
    await dir.delete(recursive: true);
  });

  group('files used by the page', () {
    test('a saved file is put in from the saved copy, with a type the page can draw',
        () async {
      files[img] = jpeg; // the server calls it application/octet-stream
      await cache.get(img);
      requests.clear();
      final html = '<img src="$base$img"><div style="background:url($base$img)"></div>';
      final out = await HtmlAssets.withSavedCopies(html, base);
      final data = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
      expect(out, '<img src="$data"><div style="background:url($data)"></div>');
      await cache.whenIdle();
      expect(requests, isEmpty); // nothing needed from the server
    });

    test('a file not saved yet stays on the server address and is saved for next time',
        () async {
      files[img] = jpeg;
      final html = '<img src="$base$img">';
      expect(await HtmlAssets.withSavedCopies(html, base), html);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(requests, [img]); // fetched in the background
      expect(await HtmlAssets.withSavedCopies(html, base), contains('data:image/jpeg'));
    });

    test('links, other servers, data addresses and logs are left alone', () async {
      files[img] = jpeg;
      await cache.get(img);
      const other = '<img src="http://example.com/a.png">'
          '<a href="/screen?x=1">go</a>'
          '<img src="data:image/png;base64,AAAA">';
      expect(await HtmlAssets.withSavedCopies(other, base), other);
      final link = '<a href="$base$img">x</a>';
      expect(await HtmlAssets.withSavedCopies(link, base), link);
      final logs = '<img src="$base/api/logs/5">';
      expect(await HtmlAssets.withSavedCopies(logs, base), logs);
    });

    test('a saved file that is too big stays on the network; no cache = page unchanged',
        () async {
      files[img] = List<int>.filled(HtmlAssets.maxInlineBytes + 1, 7);
      await cache.get(img);
      final html = '<img src="$base$img">';
      expect(await HtmlAssets.withSavedCopies(html, base), html);
      ResourceCacheHolder.instance = null;
      expect(await HtmlAssets.withSavedCopies(html, base), html);
    });

    test('the addresses a page uses are found, for the cleanup to keep them', () {
      final html = '<img src="$base$img"><div style="background:url($base/api/resources/9)">'
          '</div><img src="http://other/a.png"><a href="$base/x">y</a>'
          '<img src="$base/api/logs/3">';
      expect(HtmlAssets.addressesIn(html, base), {img, '/api/resources/9'});
    });

    test('the type: the server\'s if useful, else the file name, else the first bytes', () {
      expect(HtmlAssets.mimeOf('/a/b', 'image/webp', [1]), 'image/webp');
      expect(HtmlAssets.mimeOf('/a/b.PNG', 'application/octet-stream', [1]), 'image/png');
      expect(HtmlAssets.mimeOf('/a/b?v=2', 'application/octet-stream', [0x89, 0x50, 0x4E, 0x47]),
          'image/png');
      expect(HtmlAssets.mimeOf('/a/b', 'application/octet-stream', jpeg), 'image/jpeg');
      expect(HtmlAssets.mimeOf('/a/b', 'application/octet-stream', [1, 2]),
          'application/octet-stream');
    });

    test('a changed file is replaced by the cache and shows on the next draw',
        () async {
      files[img] = jpeg;
      await cache.get(img);
      final html = '<img src="$base$img">';
      final first = await HtmlAssets.withSavedCopies(html, base);
      final newer = [0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9, 9, 9];
      files[img] = newer;
      // a check is due (the clock is the cache's own: use a refresh to model it)
      await cache.refresh(img);
      final second = await HtmlAssets.withSavedCopies(html, base);
      expect(first, contains(base64Encode(jpeg)));
      expect(second, contains(base64Encode(newer)));
    });
  });

  group('the page itself', () {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:1'); // never used when the cache works

    test('saved on the device, read back with no server, the old copy kept if the new one fails',
        () async {
      files[page] = utf8.encode('<html>v1</html>');
      types[page] = 'text/html';
      final html =
          await LandingCache.fetchAndSave(api, 'tok', 'KIOSK_LANDING', page, 'h1');
      expect(html, '<html>v1</html>');
      expect(LocalPrefs.landingResourceUrl('KIOSK_LANDING'), page);
      expect(LandingCache.cachedHash('KIOSK_LANDING'), 'h1');
      expect(await db.select(db.cachedResources).get(), hasLength(1));

      // the server goes away: the saved page still reads
      await server.close(force: true);
      expect(await LandingCache.readHtml('KIOSK_LANDING'), '<html>v1</html>');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.statusCode = 500;
        await r.response.close();
      });
      base = 'http://127.0.0.1:${server.port}';
      // a failed refresh changes nothing
      expect(await cache.refresh(page), isNull);
      expect(await LandingCache.readHtml('KIOSK_LANDING'), '<html>v1</html>');
    });

    test('a new version replaces the page; the hash is kept for the next check',
        () async {
      files[page] = utf8.encode('<html>v1</html>');
      await LandingCache.fetchAndSave(api, 'tok', 'KIOSK_LANDING', page, 'h1');
      files[page] = utf8.encode('<html>version two</html>');
      final html =
          await LandingCache.fetchAndSave(api, 'tok', 'KIOSK_LANDING', page, 'h2');
      expect(html, '<html>version two</html>');
      expect(LandingCache.cachedHash('KIOSK_LANDING'), 'h2');
      expect(await LandingCache.readHtml('KIOSK_LANDING'), '<html>version two</html>');
      expect(dir.listSync().whereType<File>(), hasLength(1)); // old bytes removed
    });

    test('the device\'s session is sent when the page is fetched', () async {
      final seen = <String?>[];
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        seen.add(r.headers.value('authorization'));
        r.response.add(utf8.encode('<html/>'));
        await r.response.close();
      });
      base = 'http://127.0.0.1:${server.port}';
      final withToken = ResourceCache(
        db: db, dir: dir, baseUrl: () => base,
        headers: () => {'Authorization': 'Bearer tok'},
      );
      await withToken.refresh(page);
      expect(seen.single, 'Bearer tok');
      withToken.dispose();
    });
  });
}
