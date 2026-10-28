import 'package:flutter/material.dart';

import '../services/local_prefs.dart';

/// Idle-recovery timing for the kiosk. Two independent contexts: one for
/// "customer walked away mid-order", one for "customer walked away after paying." Values are
/// configuration, editable from Settings via update() — not hardcoded
/// assumptions baked into the guard widget.
class KioskTimerConfig extends ChangeNotifier {
  Duration _beforeInvoiceIdleWarningAfter;
  Duration _beforeInvoiceWarningCountdown;
  Duration _afterInvoiceIdleWarningAfter;
  Duration _afterInvoiceWarningCountdown;

  KioskTimerConfig({
    Duration beforeInvoiceIdleWarningAfter = const Duration(seconds: 60),
    Duration beforeInvoiceWarningCountdown = const Duration(seconds: 60),
    Duration afterInvoiceIdleWarningAfter = const Duration(seconds: 60),
    Duration afterInvoiceWarningCountdown = const Duration(seconds: 60),
  })  : _beforeInvoiceIdleWarningAfter = beforeInvoiceIdleWarningAfter,
        _beforeInvoiceWarningCountdown = beforeInvoiceWarningCountdown,
        _afterInvoiceIdleWarningAfter = afterInvoiceIdleWarningAfter,
        _afterInvoiceWarningCountdown = afterInvoiceWarningCountdown;

  Duration get beforeInvoiceIdleWarningAfter => _beforeInvoiceIdleWarningAfter;
  Duration get beforeInvoiceWarningCountdown => _beforeInvoiceWarningCountdown;
  Duration get afterInvoiceIdleWarningAfter => _afterInvoiceIdleWarningAfter;
  Duration get afterInvoiceWarningCountdown => _afterInvoiceWarningCountdown;

  void update({
    Duration? beforeInvoiceIdleWarningAfter,
    Duration? beforeInvoiceWarningCountdown,
    Duration? afterInvoiceIdleWarningAfter,
    Duration? afterInvoiceWarningCountdown,
    bool persist = true,
  }) {
    if (beforeInvoiceIdleWarningAfter != null) {
      _beforeInvoiceIdleWarningAfter = beforeInvoiceIdleWarningAfter;
    }
    if (beforeInvoiceWarningCountdown != null) {
      _beforeInvoiceWarningCountdown = beforeInvoiceWarningCountdown;
    }
    if (afterInvoiceIdleWarningAfter != null) {
      _afterInvoiceIdleWarningAfter = afterInvoiceIdleWarningAfter;
    }
    if (afterInvoiceWarningCountdown != null) {
      _afterInvoiceWarningCountdown = afterInvoiceWarningCountdown;
    }
    if (persist) {
      LocalPrefs.setTimers(
        beforeWarnSeconds: _beforeInvoiceIdleWarningAfter.inSeconds,
        beforeCountdownSeconds: _beforeInvoiceWarningCountdown.inSeconds,
        afterWarnSeconds: _afterInvoiceIdleWarningAfter.inSeconds,
        afterCountdownSeconds: _afterInvoiceWarningCountdown.inSeconds,
      );
    }
    notifyListeners();
  }
}

/// Global instance. Provided reactively via ChangeNotifierProvider.value in
/// main.dart.
final kioskTimerConfig = KioskTimerConfig();
