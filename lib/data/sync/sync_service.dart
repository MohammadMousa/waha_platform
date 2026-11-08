import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../services/api_client.dart';
import '../../services/trace_log.dart';
import '../../state/auth_service.dart';
import '../db/app_database.dart';
import 'activity_gate.dart';
import '../../services/local_prefs.dart';
import '../catalog/local_catalog.dart';
import '../catalog/offline_level.dart';
import '../resources/resource_cache_holder.dart';
import '../catalog/offline_mode.dart';
import '../orders/local_order_service.dart';
import '../orders/order_cleanup.dart';
import '../orders/order_push_service.dart';
import 'device_settings.dart';
import 'sync_schedule.dart';
import 'sync_settings.dart';
import 'feeds.dart';
import 'run_result.dart';
import 'sync_engine.dart';

/// Runs the pull in the background: waits for the start delay, then repeats.
/// Only works while the screen is idle, and cancels the request in flight the
/// moment a customer touches or scans.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  late final AppDatabase db = AppDatabase();
  ApiClient? _api;
  Timer? _timer;
  bool _running = false;
  Completer<void>? _abort;
  bool _manualRun = false;
  StreamSubscription<void>? _activitySub;
  SyncSettings _settings = const SyncSettings();
  // True once settings came from a real answer or from the saved copy.
  bool _settingsLoaded = false;
  OfflineLevel? _lastLevel;
  bool _pullSoon = false;

  bool get running => _running;

  /// The latest timings from /api/config (contract defaults until it loads).
  SyncSettings get settings => _settings;

  void start(ApiClient api) {
    _api = api;
    _activitySub ??= ActivityGate.instance.onActivity.listen((_) {
      if (_manualRun) return; // the person pressing Pull now is on the screen
      final a = _abort;
      if (a != null && !a.isCompleted) a.complete();
    });
    unawaited(ResourceCacheHolder.start(db, canReach: () => serverReachable));
    OfflineMode.catalog = LocalCatalog(db);
    OfflineMode.orders = LocalOrderService(db);
    OfflineMode.username = () => authService.username;
    OrderPushService.instance.start(
      db,
      settings: () => _settings,
      onAttempt: reportStatus,
      onNetwork: noteNetwork,
    );
    unawaited(_begin());
  }

  final Random _random = Random();
  // Computed once per app start and kept until the next restart.
  double _intervalJitter = 0;
  Duration? _retryAfterOverride;
  bool _offline = false;

  /// False after the server stopped answering, until it answers again.
  bool get serverReachable => !_offline;
  Timer? _probeTimer;

  Future<void> _begin() async {
    // sync_stagger_seconds is read once, here; a change applies at the next
    // restart. If the server is unreachable the defaults apply.
    await refreshSettings();
    _intervalJitter = _random.nextDouble() * 0.10; // about 10%
    var id = authService.deviceId;
    id ??= (await readDeviceSettings(db))?.deviceId;
    id ??= _random.nextInt(1 << 30); // not signed in yet: spread randomly
    final delay = SyncSchedule.startDelay(
      base: _settings.startDelay,
      deviceId: id,
      staggerSeconds: _settings.staggerSeconds,
      random: _random,
    );
    TraceLog.log('Sync: first pull in ${delay.inSeconds}s (stagger ${_settings.staggerSeconds}s)');
    _schedule(delay);
  }

  /// The push service and the pull report here whether the server answered.
  /// When it answers again after being unreachable, one pull is scheduled
  /// after a random 0 to 60 s, so a whole store coming back does not hit the
  /// server together.
  void noteNetwork(bool reachable) {
    if (!reachable) {
      if (!_offline) {
        _offline = true;
        _probeTimer ??= Timer.periodic(_settings.pushInterval, (_) async {
          try {
            final c = await _api?.getConfig(orgId: authService.organizationId);
            if (c != null && c.isNotEmpty) noteNetwork(true);
          } catch (_) {}
        });
      }
      return;
    }
    if (_offline) {
      _offline = false;
      _probeTimer?.cancel();
      _probeTimer = null;
      final d = SyncSchedule.reconnectDelay(_random);
      TraceLog.log('Sync: server reachable again, one pull in ${d.inSeconds}s');
      _schedule(d);
    }
  }

  void stop() {
    _timer?.cancel();
    _probeTimer?.cancel();
    _activitySub?.cancel();
    _activitySub = null;
    OrderPushService.instance.stop();
    final a = _abort;
    if (a != null && !a.isCompleted) a.complete();
  }

  /// Loads /api/config, keeps the timings, and remembers `offline_mode` and
  /// `scan_disabled_products` on the device so they apply after a restart
  /// even when the server cannot be reached.
  Future<void> refreshSettings() async {
    final api = _api;
    if (api == null) return;
    try {
      final c = await api.getConfig(orgId: authService.organizationId);
      // getConfig answers {} when the server cannot be reached. Never let
      // that switch offline mode off or reset the timings: keep the last ones.
      if (c.isEmpty) {
        noteNetwork(false);
        // First look after a start with no server: use the saved copy of the
        // last config instead of the built-in defaults.
        if (!_settingsLoaded) {
          final saved = LocalPrefs.savedConfig;
          if (saved.isNotEmpty) {
            _settings = SyncSettings.fromConfig(saved);
            _lastLevel = _settings.offlineLevel;
          }
          _settingsLoaded = true;
        }
        return;
      }
      noteNetwork(true);
      _settings = SyncSettings.fromConfig(c);
      // The whole answer is already saved by getConfig; the mode, the VAT
      // label and scan_disabled_products are read back from that copy.
      _settingsLoaded = true;
      final was = _lastLevel;
      _lastLevel = _settings.offlineLevel;
      // caching -> full starts the pull (after the usual random wait).
      if (was != null && was != OfflineLevel.full && _lastLevel == OfflineLevel.full) {
        _pullSoon = true;
      }
    } catch (_) {/* keep the last settings */}
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, () => unawaited(runOnce()));
  }

  /// One full cycle over every feed. Safe to call from Settings too.
  ///
  /// [manual] is the Settings button: the person pressing it is the one using
  /// the screen, so the "wait until idle" rule does not apply to that run.
  Future<RunResult> runOnce({bool manual = false}) async {
    if (_running) return const RunResult(RunKind.busy);
    _running = true;
    _manualRun = manual;
    notifyListeners();
    var rows = 0;
    try {
      await refreshSettings();
      // `caching`: no scheduled pull and no first download — reads fill the
      // local copy as they happen. The settings were refreshed above (so a
      // switch to `full` is noticed); only the Pull now button still pulls.
      if (!manual && _settings.offlineLevel == OfflineLevel.caching) {
        TraceLog.log('Sync: caching mode, no scheduled pull');
        // Still keep the device settings (store, device number, VAT, order
        // numbering): an order made locally while the server is down needs them.
        final t = authService.token;
        if (t != null) await _refreshDeviceConfig(t);
        return lastResult = const RunResult(RunKind.done, count: 0);
      }
      final token = authService.token;
      if (token == null) {
        TraceLog.log('Sync: no session, skipping this cycle');
        return lastResult = const RunResult(RunKind.noSession);
      }
      await _refreshDeviceConfig(token);
      final engine = SyncEngine(
        db: db,
        pageSize: _settings.pageSize,
        fetch: (feed, {since, required afterId, required size, required abort}) =>
            _fetch(token, feed,
                since: since, afterId: afterId, size: size, abort: abort),
      );
      for (final feed in kSyncFeeds) {
        // Wait for the screen to be idle; a customer present means we stop
        // this cycle and try again at the next interval.
        if (!manual && ActivityGate.instance.idleFor < _settings.idleNeeded) {
          TraceLog.log('Sync: customer active, pausing before $feed');
          return lastResult = const RunResult(RunKind.customerActive);
        }
        _abort = Completer<void>();
        try {
          final n = await engine.pullFeed(
            feed,
            abort: _abort!.future,
            beforeEachPage: () async {
              if (!manual &&
                  ActivityGate.instance.idleFor < _settings.idleNeeded) {
                throw const PullCancelled();
              }
            },
          );
          rows += n;
          TraceLog.log('Sync: $feed up to date ($n rows)');
        } on PullCancelled {
          TraceLog.log('Sync: $feed pull cancelled (customer active)');
          return lastResult = const RunResult(RunKind.customerActive);
        } on PullRetryAfter catch (r) {
          TraceLog.log('Sync: $feed server asked to wait ${r.delay.inSeconds}s');
          _retryAfterOverride = r.delay;
          return lastResult =
              RunResult(RunKind.serverBusy, waitSeconds: r.delay.inSeconds);
        } on PullUnauthorized {
          // Step 1 only stops. Signing out on a real 401 is wired later,
          // together with the cached-session start.
          TraceLog.log('Sync: 401 on $feed, stopping the pull');
          await engine.recordError(feed, 'unauthorized');
          return lastResult = const RunResult(RunKind.authStopped);
        } catch (e) {
          TraceLog.log('Sync: $feed failed: $e');
          if (e is! PullHttpError) noteNetwork(false); // no answer at all
          await engine.recordError(feed, e.toString());
          return lastResult = RunResult(RunKind.failed, detail: _short(e));
        } finally {
          _abort = null;
        }
      }
      return lastResult = RunResult(RunKind.done, count: rows);
    } finally {
      _running = false;
      _manualRun = false;
      lastResultAt = DateTime.now();
      unawaited(LocalPrefs.setPullAttemptAt(lastResultAt!));
      notifyListeners();
      unawaited(reportStatus());
      unawaited(_cleanup());
      final wait = _retryAfterOverride;
      _retryAfterOverride = null;
      final soon = _pullSoon;
      _pullSoon = false;
      _schedule(wait ??
          (soon ? SyncSchedule.reconnectDelay(_random) : null) ??
          _settings.interval + Duration(milliseconds: (_settings.interval.inMilliseconds * _intervalJitter).round()));
    }
  }

  /// The latest outcome of a pull, for the Settings panel.
  RunResult? lastResult;
  DateTime? lastResultAt;

  static String _short(Object e) {
    final t = e.toString().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 140 ? '${t.substring(0, 140)}…' : t;
  }

  /// Keeps the cached device settings fresh. A failure never matters here:
  /// the last saved copy stays in use.
  Future<void> _refreshDeviceConfig(String token) async {
    final client = http.Client();
    try {
      final resp = await client
          .get(Uri.parse('${AppConfig.apiBaseUrl}/api/sync/device-config'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(_settings.requestTimeout);
      if (resp.statusCode == 200) {
        final cfg = jsonDecode(resp.body) as Map<String, dynamic>;
        await saveDeviceConfig(db, cfg);
        // The device settings carry the VAT choice with its default applied;
        // it is the opposite of the online `prices_exclude_vat`.
        await LocalPrefs.setPricesExcludeVat(
            !(cfg['pricesIncludeVat'] as bool? ?? true));
      } else {
        TraceLog.log('Sync: device-config answered ${resp.statusCode}');
      }
    } catch (e) {
      TraceLog.log('Sync: device-config failed: $e');
    } finally {
      client.close();
    }
  }

  Future<void> _cleanup() async {
    if (!_settings.unpaidCleanup && !_settings.auditCleanup) return;
    try {
      final r = await runOrderCleanup(db, _settings);
      if (r.unpaidDeleted + r.sentDeleted > 0) {
        TraceLog.log('Cleanup: removed ${r.unpaidDeleted} unpaid and ${r.sentDeleted} sent local orders');
      }
    } catch (e) {
      TraceLog.log('Cleanup failed: $e');
    }
  }

  DateTime? _lastStatusAt;
  String? _lastStatusBody;

  /// POST /api/sync/status after a pull or push attempt. Sent when the
  /// numbers changed (at most once a minute), otherwise about every ten
  /// minutes. Carries the last pull time, the last accepted push time and the
  /// counts of orders waiting and failed.
  Future<void> reportStatus() async {
    final token = authService.token;
    if (token == null) return;
    final now = DateTime.now();
    final pulled = await latestPullAt(db);
    final counts = await orderCounts(db);
    final body = jsonEncode({
      if (pulled != null) 'lastPullAt': pulled,
      if (counts.lastPushAt != null) 'lastPushAt': counts.lastPushAt,
      'pendingOrders': counts.pending,
      'failedOrders': counts.dead,
    });
    final last = _lastStatusAt;
    if (last != null &&
        !SyncSchedule.shouldSendStatus(
            changed: body != _lastStatusBody, sinceLastSend: now.difference(last))) {
      return;
    }
    _lastStatusAt = now;
    final client = http.Client();
    try {
      final resp = await client
          .post(Uri.parse('${AppConfig.apiBaseUrl}/api/sync/status'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: body)
          .timeout(_settings.requestTimeout);
      if (resp.statusCode == 204) {
        _lastStatusBody = body;
      } else {
        TraceLog.log('Sync: status report answered ${resp.statusCode}');
      }
    } catch (e) {
      TraceLog.log('Sync: status report failed: $e');
    } finally {
      client.close();
    }
  }

  Future<PullPage> _fetch(
    String token,
    String feed, {
    String? since,
    required int afterId,
    required int size,
    required Future<void> abort,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/sync/$feed').replace(
      queryParameters: {
        if (since != null) 'since': since,
        if (since != null) 'afterId': '$afterId',
        'size': '$size',
      },
    );
    final client = http.Client();
    try {
      final req = http.AbortableRequest('GET', uri, abortTrigger: abort)
        ..headers['Authorization'] = 'Bearer $token';
      final streamed =
          await client.send(req).timeout(_settings.requestTimeout);
      final resp = await http.Response.fromStream(streamed)
          .timeout(_settings.requestTimeout);
      if (resp.statusCode == 401) throw const PullUnauthorized();
      if (resp.statusCode == 429 || resp.statusCode == 503) {
        final wait = SyncSchedule.parseRetryAfter(resp.headers['retry-after']);
        if (wait != null) throw PullRetryAfter(wait);
      }
      if (resp.statusCode != 200) {
        throw PullHttpError(resp.statusCode);
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final next = body['next'] as Map<String, dynamic>?;
      return PullPage(
        items: (body['items'] as List<dynamic>).cast<Map<String, dynamic>>(),
        last: body['last'] as bool,
        nextSince: next?['since'] as String?,
        nextAfterId: (next?['afterId'] as num?)?.toInt() ?? 0,
      );
    } on http.RequestAbortedException {
      throw const PullCancelled();
    } finally {
      client.close();
    }
  }
}
