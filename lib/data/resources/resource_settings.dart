/// The resource cache limits. They come from the server's organization
/// properties (read from the saved config, so they are known offline too);
/// a missing or unusable value falls back to the default.
class ResourceSettings {
  /// Total size cap of the cache.
  final int maxMb;

  /// A file NOT SHOWN for this many days is removed (counted from the last
  /// time it was shown, not from the download).
  final int maxAgeDays;

  /// At most one check for a changed version per file per this many minutes
  /// (only for addresses whose content can change, the /resource/... paths).
  final int recheckMinutes;

  const ResourceSettings({
    this.maxMb = 200,
    this.maxAgeDays = 30,
    this.recheckMinutes = 10,
  });

  Duration get recheck => Duration(minutes: recheckMinutes);
  Duration get maxAge => Duration(days: maxAgeDays);
  int get maxBytes => maxMb * 1024 * 1024;

  factory ResourceSettings.fromConfig(Map<String, String> c) {
    int n(String k, int d, int lo, int hi) =>
        (int.tryParse(c[k] ?? '') ?? d).clamp(lo, hi);
    return ResourceSettings(
      maxMb: n('resource_cache_max_mb', 200, 10, 10240),
      maxAgeDays: n('resource_cache_max_age_days', 30, 1, 365),
      recheckMinutes: n('resource_cache_recheck_minutes', 10, 1, 1440),
    );
  }
}
