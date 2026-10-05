import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/l10n/generated/app_localizations.dart';
import 'package:waha_kiosk/router/app_router.dart';
import 'package:waha_kiosk/utils/scan_actions.dart';

// Scanning unknown products must not stack dialogs, must be localized, and a
// scan notice must not stop the idle timer (the idle guard follows
// KioskRouteObserver's route name).
void main() {
  late BuildContext ctx;

  Future<void> pumpApp(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    KioskRouteObserver.currentRouteName.value = null;
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [KioskRouteObserver()],
      initialRoute: Routes.cart,
      onGenerateRoute: (s) => MaterialPageRoute(
        settings: s,
        builder: (c) => Scaffold(body: Builder(builder: (c2) {
          ctx = c2;
          return const SizedBox();
        })),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('five failed scans in a row show ONE dialog with the latest message', (tester) async {
    await pumpApp(tester);
    for (var i = 1; i <= 5; i++) {
      showScanNotFound(ctx, '000$i');
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('No product found for barcode 0005'), findsOneWidget);
    expect(find.text('No product found for barcode 0001'), findsNothing);
    expect(find.text('Scan failed'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(ScanNotice.isShowing, isTrue);
  });

  testWidgets('Arabic: title, message and OK button are in Arabic', (tester) async {
    await pumpApp(tester, locale: const Locale('ar'));
    showScanNotFound(ctx, '8888888');
    await tester.pumpAndSettle();
    expect(find.text('فشل المسح'), findsOneWidget);
    expect(find.text('لم يتم العثور على منتج بهذا الباركود: 8888888'), findsOneWidget);
    expect(find.text('حسنًا'), findsOneWidget);
    await tester.tap(find.text('حسنًا'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('not-sellable and generic failures are localized too', (tester) async {
    await pumpApp(tester, locale: const Locale('ar'));
    showScanNotSellable(ctx);
    await tester.pumpAndSettle();
    expect(find.text('هذا المنتج غير متاح للبيع حاليًا.'), findsOneWidget);
    showScanFailed(ctx, 'boom');
    await tester.pumpAndSettle();
    expect(find.text('فشل المسح: boom'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('one OK closes it, and a later failed scan shows a fresh one', (tester) async {
    await pumpApp(tester);
    showScanNotFound(ctx, 'first');
    await tester.pumpAndSettle();
    showScanNotFound(ctx, 'second');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(ScanNotice.isShowing, isFalse);

    showScanNotFound(ctx, 'third');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('No product found for barcode third'), findsOneWidget);
  });

  testWidgets('while the notice is up, the current route is still the page underneath', (tester) async {
    await pumpApp(tester);
    expect(KioskRouteObserver.currentRouteName.value, Routes.cart);
    showScanNotFound(ctx, 'x');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    // The idle guard reads this value: it must still say "cart", not "no route".
    expect(KioskRouteObserver.currentRouteName.value, Routes.cart);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(KioskRouteObserver.currentRouteName.value, Routes.cart);
  });

  testWidgets('an ordinary unnamed dialog still reads as "no named route" as before', (tester) async {
    await pumpApp(tester);
    showDialog<void>(context: ctx, builder: (_) => const AlertDialog(title: Text('x')));
    await tester.pumpAndSettle();
    expect(KioskRouteObserver.currentRouteName.value, isNull);
  });
}
