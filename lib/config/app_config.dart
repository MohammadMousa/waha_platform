import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../state/browsing_mode_service.dart';
import 'connection_settings.dart';

class AppConfig {
  AppConfig._();

  /// The Custom Connection switch and its saved fields. Listen to this to
  /// react when the active server changes (footer, native log uploader).
  static final ConnectionSettings connection = ConnectionSettings();

  static const _buildDefine = String.fromEnvironment('API_BASE_URL');

  /// Resolves in this order:
  /// 1. Custom Connection, when switched ON in Settings → Server Connection
  ///    (and its fields form a valid address). Overrides a build-time URL.
  /// 2. `--dart-define=API_BASE_URL=...` at build/run time — the project/build
  ///    default, and what Custom Connection OFF returns to.
  /// 3. Platform default — emulator alias on Android, origin host on web,
  ///    localhost elsewhere. On a real Android device this is unreachable, so
  ///    pass API_BASE_URL or turn Custom Connection on.
  ///
  /// Never hardcode a LAN IP here — use the Server Connection panel instead.
  static String get apiBaseUrl => resolveApiBaseUrl(
        customActive: connection.customActive,
        customUrl: connection.custom.url,
        buildDefine: _buildDefine,
        platformDefault: _platformDefault,
      );

  /// The default used when Custom Connection is OFF (build define, else
  /// platform default). Shown in Settings so the operator sees what OFF means.
  static String get defaultApiBaseUrl =>
      _buildDefine.isNotEmpty ? _buildDefine : _platformDefault;

  static String get _platformDefault {
    if (kIsWeb) return 'http://${Uri.base.host}:8081';
    if (Platform.isAndroid) return 'http://10.0.2.2:8081';
    return 'http://localhost:8081';
  }

  /// Pure precedence rule — see [apiBaseUrl].
  static String resolveApiBaseUrl({
    required bool customActive,
    required String customUrl,
    required String buildDefine,
    required String platformDefault,
  }) {
    if (customActive && customUrl.isNotEmpty) return customUrl;
    if (buildDefine.isNotEmpty) return buildDefine;
    return platformDefault;
  }

  /// True while a Custom Connection is overriding the project default.
  static bool get isCustomConnectionActive => connection.customActive;

  /// [apiBaseUrl] with a "(custom)" marker when it isn't the project default —
  /// for the footer and Session info.
  static String get apiBaseUrlLabel =>
      isCustomConnectionActive ? '$apiBaseUrl (custom)' : apiBaseUrl;

  /// Runs the one-time move from the old single-URL setting. Call once after
  /// LocalPrefs.init().
  static Future<void> initConnection() => connection.migrateLegacy(
        hasBuildDefine: _buildDefine.isNotEmpty,
        isAndroid: !kIsWeb && Platform.isAndroid,
      );

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
      const bool.fromEnvironment('ENABLE_SIMULATOR', defaultValue: false);
}
