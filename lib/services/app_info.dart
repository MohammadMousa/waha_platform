import 'package:package_info_plus/package_info_plus.dart';

/// Runtime read of the version baked into THIS installed build — not
/// pubspec.yaml (that's a build-time-only file; by the time the app is
/// running, Flutter has already copied its `version:` line into the
/// platform's own metadata — versionName/versionCode in the built APK on
/// Android). package_info_plus reads it back out via the platform, so this
/// always reflects what's actually installed, including on a build where
/// android/app/build.gradle.kts auto-bumped the version before compiling
/// (see tool/bump_version.py) — nothing here needs to know that happened.
class AppInfo {
  AppInfo._();

  static PackageInfo? _cached;

  /// Call once, early (e.g. app startup) so [version]/[buildNumber] below
  /// have a value by the time anything needs them synchronously. Safe to
  /// call more than once — later calls just re-fetch.
  static Future<void> init() async {
    _cached = await PackageInfo.fromPlatform();
  }

  /// "1.0.1" — the part before '+' in pubspec.yaml's version line.
  static String get version => _cached?.version ?? '?';

  /// "20260923" — the part after '+' (this project's convention: today's
  /// date, set by tool/bump_version.py on a release build).
  static String get buildNumber => _cached?.buildNumber ?? '?';

  /// When this build was made — stamped by scripts/build_release.sh through
  /// --dart-define=BUILD_TIME. A plain `flutter run` isn't stamped.
  static String get buildTime {
    const stamped = String.fromEnvironment('BUILD_TIME');
    return stamped.isEmpty ? 'not stamped (dev run)' : stamped;
  }
}
