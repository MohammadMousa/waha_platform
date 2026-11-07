import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/l10n/generated/app_localizations.dart';
import 'package:waha_kiosk/models/cart_item.dart';
import 'package:waha_kiosk/models/quote.dart';
import 'package:waha_kiosk/services/device_config.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/state/locale_service.dart';
import 'package:waha_kiosk/widgets/cart_line_tile.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
  });

  test('a missing prices_exclude_vat means VAT included', () async {
    await DeviceConfig.applyPricesExcludeVat({'offline_mode': 'false'});
    expect(LocalPrefs.pricesExcludeVat, isFalse);
  });

  test('true means VAT excluded, and an empty answer keeps the last value',
      () async {
    await DeviceConfig.applyPricesExcludeVat({'prices_exclude_vat': 'true'});
    expect(LocalPrefs.pricesExcludeVat, isTrue);

    await DeviceConfig.applyPricesExcludeVat({}); // request failed
    expect(LocalPrefs.pricesExcludeVat, isTrue);

    await DeviceConfig.applyPricesExcludeVat(
        {'prices_exclude_vat': 'false', 'x': '1'});
    expect(LocalPrefs.pricesExcludeVat, isFalse);
  });

  Future<void> pumpTile(WidgetTester tester, String lang) async {
    localeService.setLocale(Locale(lang), persist: false);
    await tester.pumpWidget(MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: Scaffold(
        body: CartLineTile(
          item: CartItem(productId: 1, name: {'en': 'Item', 'ar': 'منتج'}, quantity: 1),
          line: const QuoteLine(
              productId: 1, name: {}, quantity: 1, unitPrice: 11.5, lineTotal: 11.5),
          currency: 'SAR',
          onQuantityChanged: (_) {},
          onRemove: () {},
        ),
      ),
    ));
  }

  testWidgets('the cart line says whether the unit price includes VAT',
      (tester) async {
    await pumpTile(tester, 'en');
    expect(find.textContaining('incl. VAT'), findsOneWidget);

    await LocalPrefs.setPricesExcludeVat(true);
    await pumpTile(tester, 'en');
    expect(find.textContaining('excl. VAT'), findsOneWidget);
    expect(find.textContaining('incl. VAT'), findsNothing);

    await pumpTile(tester, 'ar');
    expect(find.textContaining('غير شامل الضريبة'), findsOneWidget);
    await LocalPrefs.setPricesExcludeVat(false);
    await pumpTile(tester, 'ar');
    expect(find.textContaining('شامل الضريبة'), findsOneWidget);
  });
}
