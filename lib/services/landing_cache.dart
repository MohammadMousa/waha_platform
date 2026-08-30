import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'local_prefs.dart';

/// Persists landing page HTML to a local file so the WebView can be shown
/// instantly on cold start, independent of network or auth state.
///
/// Files live at: <appSupportDir>/landing/{pageKey}.html
/// Content hashes live in LocalPrefs under waha.landing_hash.{pageKey}.
///
/// One entry per page key: KIOSK_LANDING, SHOPPING_LANDING,
/// CLIENT_LANDING, ADMIN_LANDING.
class LandingCache {
  LandingCache._();

  static Future<File?> _file(String pageKey) async {
    if (kIsWeb) return null;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/landing');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$pageKey.html');
  }

  /// Returns cached HTML for [pageKey], or null if never downloaded.
  static Future<String?> readHtml(String pageKey) async {
    try {
      final file = await _file(pageKey);
      if (file == null || !await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Saves [html] to disk and records [hash] in LocalPrefs.
  static Future<void> writeHtml(
      String pageKey, String html, String hash) async {
    try {
      final file = await _file(pageKey);
      if (file == null) return;
      await file.writeAsString(html);
      await LocalPrefs.setLandingHash(pageKey, hash);
    } catch (_) {}
  }

  /// Last persisted content hash for [pageKey]; null if never downloaded.
  static String? cachedHash(String pageKey) => LocalPrefs.landingHash(pageKey);

  /// Parses a bilingual title declaration near the top of an HTML landing page.
  ///
  /// Format anywhere in the first 1500 chars: title{ar=الرئيسية, en=Home}
  /// Returns the value for [lang], falling back to 'en', then any first value.
  static String? parseHtmlTitle(String html, String lang) {
    final snippet = html.length > 1500 ? html.substring(0, 1500) : html;
    final match = RegExp(r'title\{([^}]*)\}').firstMatch(snippet);
    if (match == null) return null;
    final map = <String, String>{};
    for (final part in match.group(1)!.split(',')) {
      final idx = part.indexOf('=');
      if (idx < 1) continue;
      map[part.substring(0, idx).trim()] = part.substring(idx + 1).trim();
    }
    if (map.isEmpty) return null;
    return map[lang] ?? map['en'] ?? map.values.first;
  }

  /// Rewrites absolute-path src/href/url() references in [html] to full URLs
  /// so that WebView's loadHtmlString correctly loads images and stylesheets.
  ///
  /// e.g. src="/resource/waha/..." → src="http://host:8081/resource/waha/..."
  ///
  /// Must be called before loadHtmlString every time — the raw HTML stored on
  /// disk keeps the original relative paths so it stays portable across server
  /// IP changes (the base URL is resolved fresh at display time).
  static String resolveAbsolutePaths(String html, String baseUrl) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return html
        // src="/...", href="/...", action="/..."
        .replaceAllMapped(
          RegExp(r'''((?:src|href|action)\s*=\s*["'])(/[^"']*)'''),
          (m) => '${m[1]}$base${m[2]}',
        )
        // url('/...') or url("/...") or url(/...) in CSS
        .replaceAllMapped(
          RegExp(r'''(url\s*\(\s*["']?)(/[^"')]+)'''),
          (m) => '${m[1]}$base${m[2]}',
        );
  }
}
