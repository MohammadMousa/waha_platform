import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../data/resources/resource_cache_holder.dart';
import 'api_client.dart';
import 'local_prefs.dart';

/// Persists landing page HTML so the WebView can be shown instantly on cold
/// start, independent of network or auth state.
///
/// The page is a resource like any other: it is saved by the resource cache
/// (lib/data/resources/resource_cache.dart), under the address the server
/// gave (LocalPrefs.landingResourceUrl). The files the page uses are cached
/// the same way (see HtmlAssets). The content hash the server reports is kept
/// in LocalPrefs under waha.landing_hash.{pageKey}; it is compared with the
/// server's on every check, so a check costs no download.
///
/// Where the cache does not exist (the web build) the old file is used:
/// <appSupportDir>/landing/{pageKey}.html. A file saved there by an earlier
/// version is still read until the cache holds the page.
///
/// One entry per page key (the kiosk uses KIOSK_LANDING).
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
      final cache = ResourceCacheHolder.instance;
      final address = LocalPrefs.landingResourceUrl(pageKey);
      if (cache != null && address != null) {
        final saved = await cache.peek(address);
        if (saved != null) {
          return utf8.decode(await saved.file.readAsBytes(), allowMalformed: true);
        }
      }
    } catch (_) {/* fall back to the old file */}
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

  /// Downloads the page at [resourceUrl] and saves it, returning its HTML. It
  /// goes through the resource cache (the old copy keeps showing until the new
  /// one has fully arrived); without a cache it is saved to the old file.
  /// Throws when the page cannot be fetched, as before.
  static Future<String> fetchAndSave(ApiClient api, String? token,
      String pageKey, String resourceUrl, String hash) async {
    final cache = ResourceCacheHolder.instance;
    if (cache != null) {
      final saved = await cache.refresh(resourceUrl);
      if (saved != null) {
        await LocalPrefs.setLandingResourceUrl(pageKey, resourceUrl);
        await LocalPrefs.setLandingHash(pageKey, hash);
        await _deleteOldFile(pageKey);
        return utf8.decode(await saved.file.readAsBytes(), allowMalformed: true);
      }
    }
    final html = await api.fetchResourceContent(resourceUrl, token);
    await writeHtml(pageKey, html, hash);
    return html;
  }

  static Future<void> _deleteOldFile(String pageKey) async {
    try {
      final f = await _file(pageKey);
      if (f != null && await f.exists()) await f.delete();
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

  /// Rewrites relative src/href/url() references in [html] to full URLs so
  /// that WebView's loadHtmlString correctly loads images and stylesheets.
  /// Used as a fallback for platforms (e.g. Flutter Web) where loadHtmlString
  /// ignores its baseUrl parameter and never gets a real document origin.
  ///
  /// e.g. src="/resource/waha/..."  → src="http://host:8081/resource/waha/..."
  ///      src="resource/waha/..."   → src="http://host:8081/resource/waha/..."
  ///      src="//host/resource/..." → left untouched (already a full,
  ///        protocol-relative URL — prefixing it would double the host).
  ///
  /// Must be called before loadHtmlString every time — the raw HTML stored on
  /// disk keeps the original relative paths so it stays portable across server
  /// IP changes (the base URL is resolved fresh at display time).
  static String resolveAbsolutePaths(String html, String baseUrl) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // Values that are already fully-resolvable and must not be touched:
    // absolute URLs (http/https), protocol-relative (//host/...), data URIs,
    // mailto/tel links, and same-page anchors.
    bool isAlreadyResolvable(String value) => RegExp(
          r'^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//|#)',
        ).hasMatch(value);

    String rewrite(String value) {
      if (isAlreadyResolvable(value)) return value;
      final path = value.startsWith('/') ? value : '/$value';
      return '$base$path';
    }

    return html
        // src="...", href="...", action="..." (relative or absolute path)
        .replaceAllMapped(
          RegExp(r'''((?:src|href|action)\s*=\s*["'])([^"']+)(["'])'''),
          (m) => '${m[1]}${rewrite(m[2]!)}${m[3]}',
        )
        // url('...') or url("...") or url(...) in CSS
        .replaceAllMapped(
          RegExp(r'''(url\s*\(\s*["']?)([^"')]+)(["']?\s*\))'''),
          (m) => '${m[1]}${rewrite(m[2]!)}${m[3]}',
        );
  }
}
