import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/resources/resource_cache.dart';
import 'package:waha_kiosk/data/resources/resource_cache_holder.dart';
import 'package:waha_kiosk/widgets/product_image.dart';

/// The product picture comes from the resource cache: saved on first use,
/// shown from the file after that, placeholder when there is nothing.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  // A 1x1 PNG.
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

  late AppDatabase db;
  late Directory dir;
  late HttpServer server;
  var requests = 0;

  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      dir = await Directory.systemTemp.createTemp('pimg');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      requests = 0;
      server.listen((req) async {
        requests++;
        if (req.uri.path == '/api/resources/7') {
          req.response.headers.set('etag', '"x"');
          req.response.headers.set('content-type', 'image/png');
          req.response.add(png);
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      ResourceCacheHolder.instance = ResourceCache(
          db: db, dir: dir, baseUrl: () => 'http://127.0.0.1:${server.port}');
    });
  }

  Future<void> shutdown(WidgetTester tester) async {
    await tester.runAsync(() async {
      ResourceCacheHolder.instance!.dispose();
      ResourceCacheHolder.instance = null;
      await server.close(force: true);
      await db.close();
      await dir.delete(recursive: true);
    });
  }

  // Real I/O (sockets, files, the database) finishes outside the test clock,
  // so give it real time and pump between the steps.
  Future<void> settle(WidgetTester tester, {bool expectImage = false}) async {
    // Until the picture is there (when one is expected) or the spinner is gone
    // (the placeholder is showing), at most about 5 seconds.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      final done = expectImage
          ? find.byType(Image).evaluate().isNotEmpty
          : find.byType(CircularProgressIndicator).evaluate().isEmpty;
      if (done) return;
    }
  }

  // The picture's future starts in initState, so build the widget in real time
  // too (otherwise its file and database work waits on the test clock).
  Future<void> show(WidgetTester tester, Widget w) =>
      tester.runAsync(() => tester.pumpWidget(w));

  Widget host(int? id) => MaterialApp(
        home: Scaffold(
          body: Center(child: ProductImage(imageResourceId: id, width: 60, height: 60)),
        ),
      );

  testWidgets('first view downloads and shows it; the next view needs no request',
      (tester) async {
    await boot(tester);
    await show(tester, host(7));
    expect(find.byType(CircularProgressIndicator), findsWidgets); // loading
    await settle(tester, expectImage: true);
    expect(find.byType(Image), findsOneWidget);
    expect(requests, 1);

    // shown again (a new widget): from the saved file
    await show(tester, const SizedBox());
    await show(tester, host(7));
    await settle(tester, expectImage: true);
    expect(find.byType(Image), findsOneWidget);
    expect(requests, 1);
    await shutdown(tester);
  });

  testWidgets('no picture, or one the server does not have: the placeholder',
      (tester) async {
    await boot(tester);
    await show(tester, host(null));
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    await show(tester, host(8)); // the server answers 404
    await settle(tester);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    await shutdown(tester);
  });

  testWidgets('cache not started: the placeholder, no crash', (tester) async {
    ResourceCacheHolder.instance = null;
    await show(tester, host(7));
    await tester.pump();
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('a different picture id loads the new one', (tester) async {
    await boot(tester);
    await show(tester, host(8));
    await settle(tester);
    expect(find.byType(Image), findsNothing);
    await show(tester, host(7));
    await settle(tester, expectImage: true);
    expect(find.byType(Image), findsOneWidget);
    await shutdown(tester);
  });

  testWidgets('asked to fill the width (as the grid and the sheet do): still shown',
      (tester) async {
    await boot(tester);
    await show(
        tester,
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: ProductImage(imageResourceId: 7, width: double.infinity),
            ),
          ),
        ));
    await settle(tester, expectImage: true);
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
    await shutdown(tester);
  });
}
