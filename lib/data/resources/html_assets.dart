import 'dart:convert';

import 'resource_cache.dart';
import 'resource_cache_holder.dart';

/// The files a landing page uses (its images, and anything else it loads with
/// src="..." or url(...)) are resources of their own, cached like any other.
///
/// The WebView cannot read the app's cache, and this app's WebView cannot
/// intercept requests. So, at display time and in memory only, an address
/// whose file is already saved is replaced by the saved copy inside the page.
/// The page saved on disk is never edited, and neither is the server's.
///  - Saved: the page shows the saved copy (works with no server).
///  - Not saved yet: the page keeps the server address, and the file is
///    fetched and saved in the background for the next time.
///  - A saved file that changed on the server is replaced by the cache as soon
///    as the new one has fully arrived; the page shows it the next time it is
///    drawn. Until then the page keeps showing the saved copy.
class HtmlAssets {
  HtmlAssets._();

  static final _src = RegExp(r'''(\bsrc\s*=\s*["'])([^"']+)(["'])''', caseSensitive: false);
  static final _url = RegExp(r'''(url\s*\(\s*["']?)([^"')]+)(["']?\s*\))''', caseSensitive: false);

  /// A saved file bigger than this is left on the network (it would make the
  /// page itself huge).
  static const maxInlineBytes = 3 * 1024 * 1024;

  /// The server addresses a page loads (its images and other files), from a
  /// page whose addresses are already absolute. The cleanup keeps these.
  static Set<String> addressesIn(String html, String baseUrl) {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final out = <String>{};
    for (final re in [_src, _url]) {
      for (final m in re.allMatches(html)) {
        final v = m.group(2)!;
        if (!v.startsWith('$base/')) continue;
        final a = v.substring(base.length);
        if (!ResourceCache.neverCached(a)) out.add(a);
      }
    }
    return out;
  }

  /// [html] has its addresses already made absolute (see
  /// LandingCache.resolveAbsolutePaths); [baseUrl] is the server's address.
  static Future<String> withSavedCopies(String html, String baseUrl,
      {ResourceCache? cache}) async {
    cache ??= ResourceCacheHolder.instance;
    if (cache == null) return html;
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');

    String? addressOf(String value) {
      if (!value.startsWith('$base/')) return null;
      final a = value.substring(base.length);
      return ResourceCache.neverCached(a) ? null : a;
    }

    // One pass to find the addresses, one to replace them.
    final wanted = <String>{};
    for (final re in [_src, _url]) {
      for (final m in re.allMatches(html)) {
        final a = addressOf(m.group(2)!);
        if (a != null) wanted.add(a);
      }
    }
    if (wanted.isEmpty) return html;

    final inline = <String, String>{};
    for (final a in wanted) {
      final saved = await cache.peek(a);
      if (saved == null) {
        // Lazy: fetched when the page needs it, saved for the next draw.
        cache.get(a); // ignore: unawaited_futures
        continue;
      }
      try {
        if (await saved.file.length() > maxInlineBytes) continue;
        final bytes = await saved.file.readAsBytes();
        final mime = mimeOf(a, saved.mimeType, bytes);
        inline[a] = 'data:$mime;base64,${base64Encode(bytes)}';
        cache.get(a); // ignore: unawaited_futures  (marks it shown; may check for a newer one)
      } catch (_) {/* leave the network address */}
    }
    if (inline.isEmpty) return html;

    String swap(Match m) {
      final a = addressOf(m.group(2)!);
      final data = a == null ? null : inline[a];
      return data == null ? m.group(0)! : '${m.group(1)}$data${m.group(3)}';
    }

    return html.replaceAllMapped(_src, swap).replaceAllMapped(_url, swap);
  }

  /// The type to put in the data address. The server sometimes sends
  /// application/octet-stream for a picture, which a page will not draw, so
  /// then the file name and, failing that, the first bytes decide.
  static String mimeOf(String address, String saved, List<int> bytes) {
    final s = saved.toLowerCase();
    if (s.isNotEmpty && s != 'application/octet-stream' && s != 'binary/octet-stream') {
      return s;
    }
    final path = Uri.tryParse(address)?.path.toLowerCase() ?? address.toLowerCase();
    const byExt = {
      '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
      '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml',
      '.css': 'text/css', '.js': 'text/javascript', '.woff': 'font/woff',
      '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.ico': 'image/x-icon',
    };
    for (final e in byExt.entries) {
      if (path.endsWith(e.key)) return e.value;
    }
    bool starts(List<int> sig) =>
        bytes.length >= sig.length &&
        [for (var i = 0; i < sig.length; i++) bytes[i] == sig[i]].every((x) => x);
    if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (starts([0x52, 0x49, 0x46, 0x46]) && bytes.length > 11 && bytes[8] == 0x57) {
      return 'image/webp';
    }
    return 'application/octet-stream';
  }
}
