import 'package:flutter/material.dart';

import '../services/local_prefs.dart';

/// Runtime-switchable locale — defaults to English; Settings offers an
/// EN/AR toggle. Same read-directly-or-watch-via-Provider pattern as
/// BrowsingModeService: a plain singleton, provided via
/// ChangeNotifierProvider.value for reactive rebuilds. Persists on
/// change, same reasoning as the other config services.
class LocaleService extends ChangeNotifier {
  Locale _locale;
  LocaleService(this._locale);

  Locale get locale => _locale;

  void setLocale(Locale locale, {bool persist = true}) {
    if (_locale == locale) return;
    _locale = locale;
    if (persist) {
      LocalPrefs.setLocale(locale.languageCode);
    }
    notifyListeners();
  }
}

final localeService = LocaleService(const Locale('en'));

/// Applies the organization's `default_language` property as a SEED only —
/// while nobody has ever explicitly picked a language on THIS device
/// (Settings' toggle persists via LocalPrefs.locale; this call never does).
/// Once an explicit local choice exists, this is permanently a no-op for
/// that device, even if the org's default later changes.
void applyLanguageSeed(Map<String, String> config) {
  if (LocalPrefs.locale != null) return;
  final lang = config['default_language']?.toLowerCase();
  if (lang == 'ar' || lang == 'en') {
    localeService.setLocale(Locale(lang!), persist: false);
  }
}
