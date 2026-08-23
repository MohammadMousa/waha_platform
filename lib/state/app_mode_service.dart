import 'package:flutter/material.dart';

/// The three operating modes. One app, one set of screens — this is what
/// changes HOW it's operated, not WHICH screens exist. See
/// FRONTEND_AI.md for why this replaced the old kiosk/shopping-only,
/// platform-inferred AppConfig.mode.
enum AppMode { normal, kiosk, shopping }

/// Runtime-changeable mode holder. Deliberately NOT read through Provider
/// inside onGenerateRoute (that function gets no BuildContext) — it's a
/// plain singleton that the router reads directly and that UI can also
/// `watch` via Provider.value for reactive display/switching (see
/// SimulatorSettingsScreen's mode selector).
class AppModeService extends ChangeNotifier {
  AppMode _mode;
  AppModeService(this._mode);

  AppMode get mode => _mode;

  void setMode(AppMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }
}

/// Idle-recovery timing for Kiosk mode only (per spec: Shopping/Normal
/// don't get these). Two independent contexts, matching the two-timer
/// design already agreed on: one for "customer walked away mid-order",
/// one for "customer walked away after paying." Values are configuration,
/// not architecture — these are just sensible starting defaults, editable
/// from the real Settings screen via update(), which is why fields are
/// private with notifying setters rather than public mutable fields.
class KioskTimerConfig extends ChangeNotifier {
  Duration _beforeInvoiceIdleWarningAfter;
  Duration _beforeInvoiceWarningCountdown;
  Duration _afterInvoiceIdleWarningAfter;
  Duration _afterInvoiceWarningCountdown;

  KioskTimerConfig({
    Duration beforeInvoiceIdleWarningAfter = const Duration(seconds: 45),
    Duration beforeInvoiceWarningCountdown = const Duration(seconds: 15),
    Duration afterInvoiceIdleWarningAfter = const Duration(seconds: 30),
    Duration afterInvoiceWarningCountdown = const Duration(seconds: 15),
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
    notifyListeners();
  }
}

/// Global instances. Provided reactively via ChangeNotifierProvider.value
/// in main.dart; read directly (no context needed) from onGenerateRoute.
final appModeService = AppModeService(AppMode.normal);
final kioskTimerConfig = KioskTimerConfig();
