/// Timings for the background pull. Defaults are the backend contract's
/// (offline.md section 1). The backend's /api/config will override them once
/// it sends the sync_* properties; until then the defaults apply.
class SyncSettings {
  final Duration startDelay;
  final Duration interval;
  final int pageSize;
  final Duration requestTimeout;
  final Duration idleNeeded;
  // Order push (offline.md section 1).
  final Duration pushInterval;
  final Duration pushTimeout;
  final Duration pushRetryMaxDelay;
  final bool offlineMode;
  final int staggerSeconds; // 30..3600
  // Clean-up of old local orders (server-controlled, off by default).
  final bool unpaidCleanup;
  final int cleanupDays; // 1..365
  final bool auditCleanup;

  const SyncSettings({
    this.startDelay = const Duration(seconds: 60),
    this.interval = const Duration(minutes: 60),
    this.pageSize = 200,
    this.requestTimeout = const Duration(seconds: 30),
    this.idleNeeded = const Duration(seconds: 10),
    this.pushInterval = const Duration(minutes: 3),
    this.pushTimeout = const Duration(seconds: 60),
    this.pushRetryMaxDelay = const Duration(minutes: 15),
    this.offlineMode = false,
    this.staggerSeconds = 180,
    this.unpaidCleanup = false,
    this.cleanupDays = 15,
    this.auditCleanup = false,
  });

  factory SyncSettings.fromConfig(Map<String, String> c) {
    int n(String k, int d) => int.tryParse(c[k] ?? '') ?? d;
    return SyncSettings(
      startDelay: Duration(seconds: n('sync_pull_start_delay_seconds', 60)),
      interval: Duration(minutes: n('sync_pull_interval_minutes', 60)),
      pageSize: n('sync_pull_patch_size', 200),
      requestTimeout: Duration(seconds: n('sync_pull_timeout_seconds', 30)),
      idleNeeded: Duration(seconds: n('sync_idle_seconds', 10)),
      pushInterval: Duration(minutes: n('sync_push_interval_minutes', 3)),
      pushTimeout: Duration(seconds: n('sync_push_timeout_seconds', 60)),
      pushRetryMaxDelay:
          Duration(minutes: n('sync_push_retry_max_delay_minutes', 15)),
      offlineMode: (c['offline_mode'] ?? 'false').toLowerCase() == 'true',
      staggerSeconds: n('sync_stagger_seconds', 180).clamp(30, 3600),
      unpaidCleanup: (c['offline_unpaid_cleanup_enabled'] ?? 'false').toLowerCase() == 'true',
      cleanupDays: n('offline_unpaid_cleanup_days_offset', 15).clamp(1, 365),
      auditCleanup: (c['offline_audit_cleanup'] ?? 'false').toLowerCase() == 'true',
    );
  }
}
