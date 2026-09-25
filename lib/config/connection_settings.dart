import 'package:flutter/foundation.dart';

import '../services/local_prefs.dart';

/// A user-entered server address, kept as separate parts so the Settings form
/// can edit each one and an empty port simply produces no `:port`.
///
/// Credentials are never part of this — auth/session storage stays separate.
@immutable
class CustomConnection {
  final String scheme; // 'http' | 'https'
  final String host;
  final int? port;
  final String basePath; // '' or '/something' — no trailing slash

  const CustomConnection({
    this.scheme = 'http',
    this.host = '',
    this.port,
    this.basePath = '',
  });

  static const empty = CustomConnection();

  /// Null when usable, otherwise a short message for the form.
  String? validate() {
    if (scheme != 'http' && scheme != 'https') {
      return 'Scheme must be HTTP or HTTPS';
    }
    final h = host.trim();
    if (h.isEmpty) return 'Host / IP is required';
    if (h.contains('/') || h.contains(' ') || h.contains('://')) {
      return 'Host must be a name or IP only — no scheme, slash or spaces';
    }
    final p = port;
    if (p != null && (p < 1 || p > 65535)) return 'Port must be 1–65535';
    return null;
  }

  bool get isUsable => validate() == null;

  /// `scheme://host[:port][basePath]` — no trailing slash, callers append
  /// `/api/...`. Empty string while the host is blank.
  String get url {
    final h = host.trim();
    if (h.isEmpty) return '';
    // A bare IPv6 literal needs brackets in a URL; Uri handles the rest.
    final shownHost = h.contains(':') && !h.startsWith('[') ? '[$h]' : h;
    return '$scheme://$shownHost${port != null ? ':$port' : ''}$basePath';
  }

  /// Splits a full URL into parts, or null if it isn't a usable http(s) URL.
  static CustomConnection? fromUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;
    final s = uri.scheme.toLowerCase();
    if (s != 'http' && s != 'https') return null;
    return CustomConnection(
      scheme: s,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      basePath: normalizeBasePath(uri.path),
    );
  }

  /// '' for none, otherwise a single leading slash and no trailing slash.
  static String normalizeBasePath(String raw) {
    var p = raw.trim();
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    if (p.isEmpty) return '';
    return p.startsWith('/') ? p : '/$p';
  }

  @override
  bool operator ==(Object other) =>
      other is CustomConnection &&
      other.scheme == scheme &&
      other.host == host &&
      other.port == port &&
      other.basePath == basePath;

  @override
  int get hashCode => Object.hash(scheme, host, port, basePath);
}

/// What to do with an address saved by the old single-URL setting.
class LegacyMigration {
  final CustomConnection custom;
  final bool enable;
  const LegacyMigration(this.custom, this.enable);
}

/// Pure decision used once at startup, so it can be unit-tested.
///
/// The goal is to keep every existing install on the server it already talks
/// to: with no build-time `API_BASE_URL`, the old saved URL was the active
/// one, so it becomes Custom ON. With a build-time URL, that one always won,
/// so the old saved URL is kept for later but Custom stays OFF. On Android a
/// saved `localhost` was already ignored, so it is kept but not enabled.
LegacyMigration? planLegacyMigration({
  required String? legacyUrl,
  required bool hasBuildDefine,
  required bool isAndroid,
}) {
  if (legacyUrl == null || legacyUrl.trim().isEmpty) return null;
  final parsed = CustomConnection.fromUrl(legacyUrl);
  if (parsed == null) return null;
  final ignoredLocalhost = isAndroid && legacyUrl.contains('localhost');
  return LegacyMigration(parsed, !hasBuildDefine && !ignoredLocalhost);
}

/// Owns the Custom Connection switch and its saved fields, and tells
/// listeners (footer, Settings, native log uploader) when either changes.
///
/// The fields survive the switch being turned OFF — they change only when
/// the user edits them.
class ConnectionSettings extends ChangeNotifier {
  bool get customEnabled => LocalPrefs.customConnectionEnabled;

  CustomConnection get custom => CustomConnection(
        scheme: LocalPrefs.customConnScheme,
        host: LocalPrefs.customConnHost,
        port: LocalPrefs.customConnPort,
        basePath: LocalPrefs.customConnBasePath,
      );

  /// Custom is ON *and* its fields form a valid address.
  bool get customActive => customEnabled && custom.isUsable;

  Future<void> save({
    required bool enabled,
    required CustomConnection custom,
  }) async {
    await LocalPrefs.setCustomConnection(custom);
    await LocalPrefs.setCustomConnectionEnabled(enabled);
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled == customEnabled) return;
    await LocalPrefs.setCustomConnectionEnabled(enabled);
    notifyListeners();
  }

  /// One-time move from the old `waha.api_base_url` key.
  Future<void> migrateLegacy({
    required bool hasBuildDefine,
    required bool isAndroid,
  }) async {
    final legacy = LocalPrefs.legacyApiBaseUrl;
    if (legacy == null) return;
    final plan = planLegacyMigration(
      legacyUrl: legacy,
      hasBuildDefine: hasBuildDefine,
      isAndroid: isAndroid,
    );
    if (plan != null && !custom.isUsable) {
      await LocalPrefs.setCustomConnection(plan.custom);
      await LocalPrefs.setCustomConnectionEnabled(plan.enable);
    }
    await LocalPrefs.clearLegacyApiBaseUrl();
  }
}
