import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/local_prefs.dart';

/// Platforms a mode is normally used on. Metadata, not an enforced
/// restriction — Settings still lets you pick any mode on any platform
/// for testing (see SettingsScreen), it just surfaces the mismatch rather
/// than fabricating enforcement that would get in the way of QA.
enum SupportedPlatform { web, android, desktop }

SupportedPlatform currentPlatform() {
  if (kIsWeb) return SupportedPlatform.web;
  if (Platform.isAndroid) return SupportedPlatform.android;
  return SupportedPlatform.desktop;
}

/// The three operating modes, each tagged with where it's normally used.
///
/// Normal: same experience on every platform — full navigation, whatever
/// the user has permission to reach (permissions themselves aren't built
/// yet; there's only one implicit "customer" permission level so far).
///
/// Kiosk and Shopping are alike, not opposites: both lock navigation to
/// the order flow (scan/browse → cart → checkout — the customer already
/// has, or is about to have, the item in hand). What differs is platform
/// and a couple of specifics, not the navigation model:
///  - Kiosk (android, desktop): a fixed, unchanging device identity —
///    it's the same terminal for every customer. Idle-recovery timers
///    apply, since it's a public device that can be walked away from.
///  - Shopping (web): entered via a plain webapp URL carrying a mode
///    query param (e.g. `?mode=shopping`), typically from a kiosk's own
///    QR code — the idea being the customer gets guided straight into
///    the familiar restricted flow on their own phone instead of being
///    dropped into an unfamiliar full app to figure out alone. Identity
///    is per-session (forced login, or a guest account minted on the
///    fly) rather than fixed like Kiosk's. No idle timers — it's the
///    customer's own device, no unattended-terminal risk.
///
/// Both Kiosk's device identity and Shopping's session identity need a
/// real backend auth contract before they can be built — see
/// BACKEND_CONTEXT.md. Neither is implemented yet; this enum only
/// governs navigation/timer behavior so far.
enum BrowsingMode {
  normal(SupportedPlatform.values),
  shopping([SupportedPlatform.web]),
  kiosk([SupportedPlatform.android, SupportedPlatform.desktop]);

  final List<SupportedPlatform> platforms;
  const BrowsingMode(this.platforms);

  bool get availableOnCurrentPlatform => platforms.contains(currentPlatform());
}

/// Runtime-changeable mode holder. Deliberately NOT read through Provider
/// inside onGenerateRoute (that function gets no BuildContext) — it's a
/// plain singleton that the router reads directly and that UI can also
/// `watch` via Provider.value for reactive display/switching (see
/// SettingsScreen's mode dropdown).
///
/// Persists to LocalPrefs on every change so it survives an app restart
/// or device reboot — a kiosk coming back up in Normal mode because the
/// in-memory value got lost would be a real operational incident, not
/// just an inconvenience. `persist: false` exists only for main.dart's
/// own startup load, where the value being applied *came from*
/// LocalPrefs (or is an ephemeral URL override — see AppConfig) and
/// re-saving it would be redundant or, in the URL case, actively wrong.
class BrowsingModeService extends ChangeNotifier {
  BrowsingMode _mode;
  BrowsingModeService(this._mode);

  BrowsingMode get mode => _mode;

  void setMode(BrowsingMode mode, {bool persist = true}) {
    if (_mode == mode) return;
    _mode = mode;
    if (persist) {
      LocalPrefs.setMode(mode.name);
    }
    notifyListeners();
  }
}

/// Idle-recovery timing for Kiosk mode only — Shopping's navigation is
/// just as locked as Kiosk's, but per the doc above it doesn't get
/// timers, since there's no unattended-device risk on a customer's own
/// phone. Two independent contexts: one for "customer walked away
/// mid-order", one for "customer walked away after paying." Values are
/// configuration, editable from Settings via update() — not hardcoded
/// assumptions baked into the guard widget.
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

/// Parses a persisted mode name back into the enum — returns null rather
/// than throwing on a value that doesn't match (a stale/corrupt pref
/// shouldn't crash startup, just fall through to the next resolution
/// step in AppConfig).
BrowsingMode? parseBrowsingMode(String? name) {
  if (name == null) return null;
  for (final m in BrowsingMode.values) {
    if (m.name == name) return m;
  }
  return null;
}

/// Global instances. Provided reactively via ChangeNotifierProvider.value
/// in main.dart; read directly (no context needed) from onGenerateRoute.
final browsingModeService = BrowsingModeService(BrowsingMode.normal);
final kioskTimerConfig = KioskTimerConfig();
