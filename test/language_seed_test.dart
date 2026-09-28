import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/state/locale_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    localeService.setLocale(const Locale('en'), persist: false);
  });

  test('applies the org default when nobody has picked a language locally',
      () {
    applyLanguageSeed({'default_language': 'ar'});
    expect(localeService.locale, const Locale('ar'));
  });

  test('never overwrites an explicit local choice', () async {
    await LocalPrefs.setLocale('en'); // operator picked English in Settings
    applyLanguageSeed({'default_language': 'ar'});
    expect(localeService.locale, const Locale('en'));
  });

  test('ignores an unknown or missing language value', () {
    applyLanguageSeed({'default_language': 'fr'});
    expect(localeService.locale, const Locale('en'));
    applyLanguageSeed({});
    expect(localeService.locale, const Locale('en'));
  });
}
