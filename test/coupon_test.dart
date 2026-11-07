import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/l10n/generated/app_localizations.dart';
import 'package:waha_kiosk/models/cart_item.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/api_exceptions.dart';
import 'package:waha_kiosk/services/app_messenger.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/state/order_flow_controller.dart';
import 'package:waha_kiosk/utils/coupon_text.dart';
import 'package:waha_kiosk/utils/scanner_manager.dart';

/// A fake server: GOOD and OTHER are accepted, MIN is accepted only while
/// the cart holds 2 or more, anything else is refused as expired.
class _Fake {
  late HttpServer server;
  final quotes = <Map<String, dynamic>>[];
  final orders = <Map<String, dynamic>>[];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body =
          jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      var status = 200;
      Object out = {};
      final code = body['couponCode'] as String?;
      final qty = (body['items'] as List).fold<int>(
          0, (a, e) => a + ((e as Map)['quantity'] as int));
      if (req.uri.path == '/api/orders/quote') {
        quotes.add(body);
      } else if (req.uri.path == '/api/orders') {
        orders.add(body);
      }
      String? error;
      if (code != null) {
        if (code == 'MIN') {
          if (qty < 2) error = 'COUPON_MINIMUM_ORDER_NOT_MET';
        } else if (code != 'GOOD' && code != 'OTHER') {
          error = 'COUPON_EXPIRED';
        }
      }
      if (error != null) {
        status = 422;
        out = {'error': error, 'message': 'refused'};
      } else if (req.uri.path == '/api/orders/quote') {
        out = {
          'subtotal': 10.0,
          'tax': 1.5,
          'total': 11.5 - (code == null ? 0 : 2.0),
          'discountAmount': code == null ? 0.0 : 2.0,
          'items': [],
          if (code != null)
            'coupon': {'code': code, 'name': 'Test', 'discountAmount': 2.0},
        };
      } else {
        out = {
          'orderId': body['orderId'],
          'status': 'CREATED',
          'items': [],
          'subtotal': 10.0,
          'tax': 1.5,
          'total': 11.5,
          'currency': 'SAR',
          'createdAt': '2026-11-07T10:00:00',
        };
      }
      req.response.statusCode = status;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(out));
      await req.response.close();
    });
  }
}

CartItem _item(int qty) =>
    CartItem(productId: 1, name: {'en': 'Item'}, quantity: qty);

void main() {
  late _Fake fake;
  late OrderFlowController flow;

  // The widget test binding blocks real HTTP; this file talks to a local fake.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    fake = _Fake();
    await fake.start();
    flow = OrderFlowController(
        ApiClient(baseUrl: 'http://127.0.0.1:${fake.server.port}'));
  });
  tearDown(() => fake.server.close(force: true));

  test('an accepted coupon is kept and sent with later quotes', () async {
    flow.cart.add(_item(2));
    final q = await flow.applyCoupon('GOOD');
    expect(q.coupon?.code, 'GOOD');
    expect(flow.couponCode, 'GOOD');
    expect(flow.quote?.discountAmount, 2.0);

    await flow.updateQuantity(1, 3);
    expect(fake.quotes.last['couponCode'], 'GOOD');
  });

  test('a refused coupon changes nothing and says why', () async {
    flow.cart.add(_item(2));
    await flow.applyCoupon('GOOD');
    await expectLater(
      flow.applyCoupon('NOPE'),
      throwsA(isA<CouponRejectedException>()
          .having((e) => e.code, 'code', 'COUPON_EXPIRED')),
    );
    expect(flow.couponCode, 'GOOD'); // the earlier coupon stays
  });

  test('a second coupon replaces the first once the server accepts it',
      () async {
    flow.cart.add(_item(2));
    await flow.applyCoupon('GOOD');
    await flow.applyCoupon('OTHER');
    expect(flow.couponCode, 'OTHER');
  });

  test('a coupon is dropped when the cart later falls below its minimum',
      () async {
    flow.cart.add(_item(2));
    await flow.applyCoupon('MIN');
    expect(flow.couponCode, 'MIN');

    await flow.updateQuantity(1, 1); // below the minimum now
    expect(flow.couponCode, isNull);
    expect(flow.quote?.coupon, isNull);
    expect(flow.quote?.discountAmount, 0.0);
  });

  test('the coupon is cleared when the cart is emptied', () async {
    flow.cart.add(_item(2));
    await flow.applyCoupon('GOOD');
    await flow.removeItem(1);
    expect(flow.couponCode, isNull);
  });

  test('the order carries the coupon, then the cart forgets it', () async {
    flow.cart.add(_item(2));
    await flow.applyCoupon('GOOD');
    await flow.checkout();
    expect(fake.orders.single['couponCode'], 'GOOD');
    expect(flow.couponCode, isNull);
  });

  test('removing the coupon prices the cart without it', () async {
    flow.cart.add(_item(2));
    await flow.applyCoupon('GOOD');
    await flow.removeCoupon();
    expect(flow.couponCode, isNull);
    expect(fake.quotes.last.containsKey('couponCode'), isFalse);
  });

  test('with the server unreachable a coupon is not accepted', () async {
    final dead = OrderFlowController(ApiClient(baseUrl: 'http://127.0.0.1:1'));
    dead.cart.add(_item(2));
    await expectLater(dead.applyCoupon('GOOD'), throwsA(anything));
    expect(dead.couponCode, isNull);
  });

  test('every server error code has its own text in both languages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final ar = lookupAppLocalizations(const Locale('ar'));
    const codes = [
      'COUPON_NOT_FOUND', 'COUPON_DISABLED', 'COUPON_NOT_YET_VALID',
      'COUPON_EXPIRED', 'COUPON_WRONG_STORE', 'COUPON_USAGE_LIMIT_REACHED',
      'COUPON_USER_LIMIT_REACHED', 'COUPON_AMOUNT_EXHAUSTED',
      'COUPON_USER_AMOUNT_EXHAUSTED', 'COUPON_MINIMUM_ORDER_NOT_MET',
      'COUPON_NOT_COMBINABLE', 'COUPON_NOT_APPLICABLE',
    ];
    final seen = <String>{};
    for (final c in codes) {
      expect(couponErrorText(en, c), isNot(en.couponErrGeneric), reason: c);
      expect(couponErrorText(ar, c), isNot(ar.couponErrGeneric), reason: c);
      expect(seen.add(couponErrorText(en, c)), isTrue, reason: 'unique $c');
    }
    expect(couponErrorText(en, 'SOMETHING_NEW'), en.couponErrGeneric);
  });

  Future<(BuildContext, OrderFlowController)> pump(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: flow,
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      ),
    ));
    return (ctx, flow);
  }

  testWidgets('scanning a coupon: not a coupon, empty cart, open order, ok',
      (tester) async {
    final (ctx, f) = await pump(tester);
    final m = ScannerManager.instance;

    expect(await m.handleCoupon(ctx, '6281000123456'), isFalse);

    // empty cart
    expect(await m.handleCoupon(ctx, 'coupon=GOOD'), isTrue);
    await tester.pump();
    expect(find.text('Add some items to the cart first'), findsOneWidget);
    expect(f.couponCode, isNull);

    // an unpaid order is open: not at this stage
    f.cart.add(_item(2));
    f.orderId = 'abc';
    expect(await m.handleCoupon(ctx, 'coupon=GOOD'), isTrue);
    await tester.pump();
    expect(find.text("Coupons can't be added at this stage"), findsOneWidget);
    expect(f.couponCode, isNull);
    f.orderId = null;

    // bad format never reaches the server
    final before = fake.quotes.length;
    expect(await m.handleCoupon(ctx, 'coupon=a b'), isTrue);
    expect(fake.quotes.length, before);

    // a good one
    await tester.runAsync(() => m.handleCoupon(ctx, 'coupon=GOOD'));
    await tester.pump();
    expect(f.couponCode, 'GOOD');
    expect(find.text('Coupon GOOD applied'), findsOneWidget);
  });

  testWidgets('scanning a coupon with the server unreachable says so',
      (tester) async {
    final (ctx, _) = await pump(tester);
    final dead = OrderFlowController(ApiClient(baseUrl: 'http://127.0.0.1:1'));
    dead.cart.add(_item(2));
    late BuildContext dctx;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: dead,
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: Scaffold(body: Builder(builder: (c) {
          dctx = c;
          return const SizedBox();
        })),
      ),
    ));
    expect(ctx, isNotNull);
    await tester.runAsync(
        () => ScannerManager.instance.handleCoupon(dctx, 'coupon=GOOD'));
    await tester.pump();
    expect(find.textContaining("Can't reach the server"), findsOneWidget);
    expect(dead.couponCode, isNull);
  });
}
