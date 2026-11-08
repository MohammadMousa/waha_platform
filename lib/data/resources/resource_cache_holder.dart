import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';
import '../../services/local_prefs.dart';
import '../../state/auth_service.dart';
import '../db/app_database.dart';
import '../../services/landing_cache.dart';
import '../sync/activity_gate.dart';
import 'html_assets.dart';
import 'resource_cache.dart';
import 'resource_settings.dart';

/// The one [ResourceCache] of the app (null until started, and on the web,
/// which has no disk: screens then fall back to the network).
class ResourceCacheHolder {
  ResourceCacheHolder._();

  static ResourceCache? instance;

  /// Starts the cache on the app's database. [canReach] says whether the
  /// server answered recently (offline: saved files only, no checks).
  static Future<void> start(AppDatabase db, {bool Function()? canReach}) async {
    if (kIsWeb || instance != null) return;
    final base = await getApplicationSupportDirectory();
    instance = ResourceCache(
      db: db,
      dir: Directory('${base.path}/resources'),
      baseUrl: () => AppConfig.apiBaseUrl,
      // The landing page is fetched with the device's session, as before.
      headers: () {
        final t = authService.token;
        return t == null ? const {} : {'Authorization': 'Bearer $t'};
      },
      canReach: canReach,
      // The limits come from the server's properties, read from the saved
      // config so they are known offline too.
      settings: () => ResourceSettings.fromConfig(LocalPrefs.savedConfig),
      // Kept by the cleanup: the landing page and every file it uses.
      pinned: _landingFiles,
      // Cleanup waits until nobody is using the screen.
      isIdle: () => ActivityGate.instance.idleFor >= const Duration(seconds: 30),
    );
    instance!.startDailyCleanup();
    _removeOldImagePackageCache();
  }

  /// The landing page's own address and the files its saved copy uses.
  static Future<Set<String>> _landingFiles() async {
    const pageKey = 'KIOSK_LANDING';
    final out = <String>{};
    final address = LocalPrefs.landingResourceUrl(pageKey);
    if (address != null) out.add(address);
    final html = await LandingCache.readHtml(pageKey);
    if (html != null) {
      final base = AppConfig.apiBaseUrl;
      out.addAll(HtmlAssets.addressesIn(
          LandingCache.resolveAbsolutePaths(html, base), base));
    }
    return out;
  }

  /// The image package used before this cache kept its own files; they are
  /// not reused, so they are deleted once to free the space.
  static Future<void> _removeOldImagePackageCache() async {
    try {
      final tmp = await getTemporaryDirectory();
      final old = Directory('${tmp.path}/libCachedImageData');
      if (await old.exists()) await old.delete(recursive: true);
    } catch (_) {}
  }
}
