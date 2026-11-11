import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/l10n/generated/app_localizations.dart';
import 'package:waha_kiosk/models/order.dart';
import 'package:waha_kiosk/screens/qr_payment_screen.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

WahaOrder _order(String status) => WahaOrder(
      orderId: 'o1',
      status: status,
      subtotal: 1,
      tax: 0.15,
      total: 1.15,
      items: const [],
    );

class _PopCounter extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

/// The server's way: one "paid" event, then it closes the connection.
http.Client _paidThenClosed() => MockClient.streaming((req, _) async =>
    http.StreamedResponse(
        Stream.value(utf8.encode('event: payment_confirmed\ndata: PAID\n\n')),
        200));

/// A connection that ends quietly without ever saying "paid".
http.Client _closedQuietly() => MockClient.streaming(
    (req, _) async => http.StreamedResponse(const Stream.empty(), 200));

Future<_PopCounter> _open(
  WidgetTester tester, {
  required Future<WahaOrder> Function() refresh,
  required http.Client Function() client,
  List<Object?>? results,
}) async {
  final obs = _PopCounter();
  await tester.pumpWidget(MaterialApp(
    navigatorObservers: [obs],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final r = await showDialog<WahaOrder>(
              context: context,
              barrierDismissible: false,
              builder: (_) => Dialog(
                child: QrPaymentScreen(
                  orderId: 'o1',
                  qrCodeDataUri: 'data:image/png;base64,$_png',
                  expiresAt: DateTime.now().add(const Duration(minutes: 15)),
                  methodLabel: 'Test',
                  onRefreshOrder: refresh,
                  pollInterval: const Duration(seconds: 3),
                  clientFactory: client,
                ),
              ),
            );
            results?.add(r);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  obs.pops = 0;
  return obs;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
  });

  testWidgets(
      'paid event followed by the connection closing closes the QR screen once',
      (tester) async {
    var calls = 0;
    final results = <Object?>[];
    final obs = await _open(
      tester,
      client: _paidThenClosed,
      results: results,
      // The two checks come back a few milliseconds apart, as in the field.
      refresh: () async {
        calls++;
        await Future<void>.delayed(Duration(milliseconds: calls == 1 ? 5 : 30));
        return _order('PAID');
      },
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Closed straight away (no "confirmed" step), and only once.
    expect(obs.pops, 1, reason: 'exactly one screen may be closed');
    await tester.pump(const Duration(seconds: 2));
    expect(obs.pops, 1);
    expect(results.length, 1);
    expect((results.single as WahaOrder).status, 'PAID');
  });

  testWidgets(
      'a connection that dies quietly does not stop the screen learning of the payment',
      (tester) async {
    var calls = 0;
    final results = <Object?>[];
    final obs = await _open(
      tester,
      client: _closedQuietly,
      results: results,
      // Not paid for the first checks (the customer is still paying).
      refresh: () async => _order(++calls < 6 ? 'PENDING' : 'PAID'),
    );
    // About 2 minutes later the order turns paid on the server.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    await tester.pump(const Duration(seconds: 2));
    expect(results.length, 1);
    expect((results.single as WahaOrder).status, 'PAID');
    expect(obs.pops, 1);
  });

  testWidgets('checks never overlap while one is still waiting for the server',
      (tester) async {
    var running = 0;
    var maxRunning = 0;
    await _open(
      tester,
      client: _closedQuietly,
      refresh: () async {
        running++;
        if (running > maxRunning) maxRunning = running;
        await Future<void>.delayed(const Duration(seconds: 10));
        running--;
        return _order('PENDING');
      },
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    expect(maxRunning, 1);
    // Close the screen and let the pretend slow server answer before the end.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });
}
