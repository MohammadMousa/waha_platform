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
