import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../state/browsing_mode_service.dart';

class AppConfig {
  AppConfig._();

  /// ── Physical Android device dev switch ───────────────────────────────
  /// `10.0.2.2` (the Android default below) is a NAT alias that only
  /// resolves inside the Android *emulator* — it points nowhere on a real
  /// phone. When testing on a real device (USB or wifi) against the
  /// Docker backend running on this laptop, flip [_useLanBackendForDevice]
  /// to `true` and point [_lanBackendUrl] at the laptop's current LAN IP
  /// (`ip -4 addr show` → the wifi interface, e.g. wlp2s0) plus the
  /// Docker-published port (8081 here, not the container-internal 8080).
  /// Flip back to `false` before switching back to the emulator, and
  /// don't commit this as `true` — it only affects `Platform.isAndroid`,
  /// so web/desktop/emulator runs are untouched either way.
  static const bool _useLanBackendForDevice = true;
  static const String _lanBackendUrl = 'http://192.168.1.3:8081';

  /// Resolves in this order:
  /// 1. `--dart-define=API_BASE_URL=...` at build/run time (always wins —
  ///    this is how a real kiosk pointed at a LAN backend IP gets configured).
  /// 2. The dev switch above, Android only.
  /// 3. Platform-sensible dev default, matching FRONTEND_CONTEXT.md.
  ///    Port 8081 — the backend's host-side port, distinct from the
  ///    container's own internal 8080; only matters for the URL callers
  ///    outside the container use.
  ///
  /// Never hardcode this elsewhere in the app — always go through here.
  static String get apiBaseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;

    if (kIsWeb) return 'http://localhost:8081';
    if (Platform.isAndroid) {
      return _useLanBackendForDevice ? _lanBackendUrl : 'http://10.0.2.2:8081';
    }
    // Desktop dev fallback (not a Phase 1 target, but harmless to have).
    return 'http://localhost:8081';
  }

  /// Web-only, ephemeral: a `?mode=` URL query param. This is the actual
  /// real-world mechanism for entering Shopping mode — a customer scans a
  /// QR or opens a link carrying `?mode=shopping`, typically printed on/
  /// shown by a kiosk, and lands straight in the restricted flow on their
  /// own phone. Deliberately never persisted (see main.dart's startup
  /// resolution) — it's a per-link, per-visit override, not a durable
  /// device setting. Persisting it would mean one Shopping QR scan
  /// permanently converts that browser to Shopping mode for every future
  /// visit, which isn't what "guest scans a link" is supposed to mean.
  static BrowsingMode? get urlOverrideMode {
    if (!kIsWeb) return null;
    final param = Uri.base.queryParameters['mode']?.toLowerCase();
    if (param == 'shopping') return BrowsingMode.shopping;
    if (param == 'kiosk') return BrowsingMode.kiosk;
    if (param == 'normal') return BrowsingMode.normal;
    return null;
  }

  /// Build-time mode override — `--dart-define=APP_MODE=kiosk|shopping|
  /// normal`. Used only as a first-run seed (see main.dart): once a mode
  /// is persisted, the persisted value wins on every subsequent launch,
  /// even if this dart-define is still set the same way in a rebuilt
  /// APK — otherwise Settings' mode switch would get silently reverted
  /// on every restart of a build that bakes in a fixed APP_MODE.
  static BrowsingMode? get dartDefineMode {
    const override = String.fromEnvironment('APP_MODE');
    if (override == 'kiosk') return BrowsingMode.kiosk;
    if (override == 'shopping') return BrowsingMode.shopping;
    if (override == 'normal') return BrowsingMode.normal;
    return null;
  }

  /// Simulator buttons must never be reachable on a real release build.
  /// Compiled out via --dart-define, not just hidden behind a settings
  /// toggle — see the leaked-setting concern raised earlier.
  static bool get simulatorAvailable =>
      const bool.fromEnvironment('ENABLE_SIMULATOR', defaultValue: true);
}

