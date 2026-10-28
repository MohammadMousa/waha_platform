import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

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

  /// Simulator buttons must never be reachable on a real release build.
  /// Compiled out via --dart-define, not just hidden behind a settings
  /// toggle — see the leaked-setting concern raised earlier.
  static bool get simulatorAvailable =>
      const bool.fromEnvironment('ENABLE_SIMULATOR', defaultValue: false);
}
