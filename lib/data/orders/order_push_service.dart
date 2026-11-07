import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../services/trace_log.dart';
import '../../state/auth_service.dart';
import '../db/app_database.dart';
import '../sync/sync_schedule.dart';
import '../sync/sync_settings.dart';
import 'local_order_service.dart';
import '../sync/run_result.dart';

/// What happened to one push attempt.
sealed class PushOutcome {
  const PushOutcome();
}

class PushAccepted extends PushOutcome {
  final String result; // CREATED | UPDATED | ALREADY_SYNCED
  final int? displayId;
  const PushAccepted(this.result, this.displayId);
}

/// The server will never accept this order as it is: dead-letter list.
class PushRejected extends PushOutcome {
  final String code;
  final String message;
  const PushRejected(this.code, this.message);
}

/// Worth trying again later (server busy or unreachable).
class PushRetry extends PushOutcome {
  final String message;
  /// The server's `Retry-After`, if it sent one.
  final Duration? retryAfter;
  const PushRetry(this.message, {this.retryAfter});
}

/// 401/403: stop sending, keep every order, show a warning.
class PushAuthStop extends PushOutcome {
  final int status;
  const PushAuthStop(this.status);
}

/// Turns the server's answer into an outcome (offline.md section 6).
PushOutcome classifyPushResponse(int status, String body, {Duration? retryAfter}) {
  Map<String, dynamic> json = const {};
  try {
    final d = jsonDecode(body);
    if (d is Map<String, dynamic>) json = d;
  } catch (_) {}
  if (status == 200) {
    return PushAccepted(
        (json['result'] as String?) ?? 'CREATED', (json['displayId'] as num?)?.toInt());
  }
  if (status == 401 || status == 403) return PushAuthStop(status);
  final code = (json['error'] as String?) ?? 'HTTP_$status';
  final message = (json['message'] as String?) ?? 'Request failed ($status)';
  if (status >= 500 || status == 408 || status == 429) {
    return PushRetry('$code: $message', retryAfter: retryAfter);
  }
  // Any other 4xx: permanent unless the server says it may be retried.
  if (json['retryable'] == true) return PushRetry('$code: $message');
  return PushRejected(code, message);
}

/// Delay before the next try: the push interval doubled per failed attempt,
/// capped at [max].
Duration pushBackoff(int attempts, Duration base, Duration max) {
  final factor = math.pow(2, math.min(attempts, 20)).toInt();
  final ms = base.inMilliseconds * factor;
  return ms >= max.inMilliseconds ? max : Duration(milliseconds: ms);
}

class OrderCounts {
  final int pending;
  final int dead;
  final String? lastPushAt;
  const OrderCounts(this.pending, this.dead, this.lastPushAt);
}

Future<OrderCounts> orderCounts(AppDatabase db) async {
  Future<int> count(String state) async {
    final c = countAll();
    final q = db.selectOnly(db.localOrders)
      ..addColumns([c])
      ..where(db.localOrders.syncState.equals(state));
    return (await q.getSingle()).read(c) ?? 0;
  }

  final m = db.localOrders.syncedAt.max();
  final last = await (db.selectOnly(db.localOrders)..addColumns([m])).getSingle();
  return OrderCounts(await count('PENDING'), await count('DEAD'), last.read(m));
}

/// Sends paid local orders to the server. Runs on its own timer and is never
/// paused by customer activity. A rejected order goes to the dead-letter list
/// (kept in the database) and the others keep going.
class OrderPushService extends ChangeNotifier {
  OrderPushService._({http.Client? client}) : _client = client;
  static final OrderPushService instance = OrderPushService._();

  /// For tests: a service with its own HTTP client, database and clock.
  @visibleForTesting
  OrderPushService.test({
    required http.Client client,
    required AppDatabase database,
    SyncSettings? settings,
    String? Function()? token,
    DateTime Function()? now,
    String baseUrl = 'http://test',
    math.Random? random,
  })  : _client = client,
        _random = random ?? math.Random(),
        _db = database,
        _settings = (() => settings ?? const SyncSettings()),
        _tokenOverride = token,
        _nowOverride = now,
        _baseUrlOverride = baseUrl;

  final http.Client? _client;
  math.Random _random = math.Random();
  AppDatabase? _db;
  SyncSettings Function() _settings = () => const SyncSettings();
  Future<void> Function()? _onAttempt;
  void Function(bool reachable)? _onNetwork;
  String? Function()? _tokenOverride;
  DateTime Function()? _nowOverride;
  String? _baseUrlOverride;
  Timer? _timer;
  bool _running = false;

  /// True after a 401/403: sending is stopped until the next successful
  /// authenticated try. Shown as a warning in Settings.
  bool authBlocked = false;
  bool get running => _running;

  /// The latest outcome of a send pass, for the Settings panel.
  RunResult? lastResult;
  DateTime? lastResultAt;

  static String _short(String t) {
    final c = t.replaceAll(RegExp(r'\s+'), ' ');
    return c.length > 140 ? '${c.substring(0, 140)}…' : c;
  }

  DateTime _now() => (_nowOverride ?? DateTime.now)().toUtc();
  String? _token() => _tokenOverride != null ? _tokenOverride!() : authService.token;
  String get _base => _baseUrlOverride ?? AppConfig.apiBaseUrl;

  void start(
    AppDatabase db, {
    required SyncSettings Function() settings,
    Future<void> Function()? onAttempt,
    void Function(bool reachable)? onNetwork,
  }) {
    _db = db;
    _settings = settings;
    _onAttempt = onAttempt;
    _onNetwork = onNetwork;
    _timer?.cancel();
    _schedule();
  }

  void stop() => _timer?.cancel();

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_settings().pushInterval, () async {
      await pushPending();
      _schedule();
    });
  }

  /// One pass over every paid order that is waiting and due. Safe to call at
  /// any time, for example right after an order was paid.
  Future<RunResult> pushPending() async {
    final db = _db;
    if (db == null || _running) return const RunResult(RunKind.busy);
    final token = _token();
    if (token == null) return lastResult = const RunResult(RunKind.noSession);
    _running = true;
    notifyListeners();
    var attempted = false;
    var sent = 0;
    var rejected = 0;
    try {
      final nowIso = _now().toIso8601String();
      // A retry time further away than the longest back-off (plus its jitter)
      // can only come from a device clock that was set backwards: send now.
      final s = _settings();
      final farIso = _now()
          .add(Duration(milliseconds: (s.pushRetryMaxDelay.inMilliseconds * 1.5).round()))
          .toIso8601String();
      final due = await (db.select(db.localOrders)
            ..where((t) =>
                t.syncState.equals('PENDING') &
                (t.nextAttemptAt.isNull() |
                    t.nextAttemptAt.isSmallerOrEqualValue(nowIso) |
                    t.nextAttemptAt.isBiggerThanValue(farIso)))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
      final svc = LocalOrderService(db);
      for (final o in due) {
        attempted = true;
        final outcome = await _send(token, await svc.buildPushBody(o.orderId));
        switch (outcome) {
          case PushAccepted():
            authBlocked = false;
            await _markSynced(db, o.orderId, outcome.displayId);
            sent++;
            TraceLog.log('Push: ${o.orderReference} ${outcome.result}');
          case PushRejected():
            await _markDead(db, o.orderId, outcome.code, outcome.message);
            rejected++;
            TraceLog.log('Push: ${o.orderReference} rejected ${outcome.code}');
          case PushRetry():
            await _markRetry(db, o, outcome.message, outcome.retryAfter);
            TraceLog.log('Push: ${o.orderReference} will retry: ${outcome.message}');
            // The server is busy or unreachable: don't hammer it with the rest.
            notifyListeners();
            return lastResult = RunResult(RunKind.failed,
                count: sent,
                rejected: rejected,
                detail: _short(outcome.message));
          case PushAuthStop():
            authBlocked = true;
            TraceLog.log('Push: ${outcome.status}, stopping; orders kept');
            notifyListeners();
            return lastResult = RunResult(RunKind.authStopped,
                count: sent, rejected: rejected);
        }
        notifyListeners();
      }
      return lastResult =
          RunResult(RunKind.done, count: sent, rejected: rejected);
    } finally {
      _running = false;
      lastResultAt = DateTime.now();
      notifyListeners();
      if (attempted) {
        final cb = _onAttempt;
        if (cb != null) unawaited(cb());
      }
    }
  }

  Future<PushOutcome> _send(String token, Map<String, dynamic> body) async {
    try {
      final resp = await (_client ?? http.Client())
          .post(
            Uri.parse('$_base/api/sync/orders'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_settings().pushTimeout);
      _onNetwork?.call(true);
      return classifyPushResponse(resp.statusCode, resp.body,
          retryAfter: SyncSchedule.parseRetryAfter(resp.headers['retry-after'], now: _now()));
    } catch (e) {
      _onNetwork?.call(false);
      return PushRetry('network: $e');
    }
  }

  Future<void> _markSynced(AppDatabase db, String id, int? displayId) =>
      (db.update(db.localOrders)..where((t) => t.orderId.equals(id))).write(
        LocalOrdersCompanion(
          syncState: const Value('SYNCED'),
          displayId: Value(displayId),
          syncedAt: Value(_now().toIso8601String()),
          nextAttemptAt: const Value(null),
          lastErrorCode: const Value(null),
          lastError: const Value(null),
        ),
      );

  Future<void> _markDead(AppDatabase db, String id, String code, String msg) =>
      (db.update(db.localOrders)..where((t) => t.orderId.equals(id))).write(
        LocalOrdersCompanion(
          syncState: const Value('DEAD'),
          lastErrorCode: Value(code),
          lastError: Value(msg),
          nextAttemptAt: const Value(null),
        ),
      );

  Future<void> _markRetry(AppDatabase db, LocalOrder o, String msg, Duration? retryAfter) {
    final s = _settings();
    final attempts = o.attempts + 1;
    // Back-off with about 20% random jitter, never shorter than a Retry-After.
    var wait = SyncSchedule.withJitter(
        pushBackoff(attempts, s.pushInterval, s.pushRetryMaxDelay), 0.20, _random);
    if (retryAfter != null && retryAfter > wait) wait = retryAfter;
    final next = _now().add(wait);
    return (db.update(db.localOrders)..where((t) => t.orderId.equals(o.orderId))).write(
      LocalOrdersCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(next.toIso8601String()),
        lastError: Value(msg),
      ),
    );
  }

  // ---- Dead-letter list ----------------------------------------------------

  Future<List<LocalOrder>> deadOrders() {
    final db = _db!;
    return (db.select(db.localOrders)
          ..where((t) => t.syncState.equals('DEAD'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Puts a dead-lettered order back in the queue (the Retry button).
  Future<void> retryDead(String orderId) async {
    final db = _db!;
    await (db.update(db.localOrders)..where((t) => t.orderId.equals(orderId))).write(
      const LocalOrdersCompanion(
        syncState: Value('PENDING'),
        attempts: Value(0),
        nextAttemptAt: Value(null),
        lastErrorCode: Value(null),
        lastError: Value(null),
      ),
    );
    notifyListeners();
  }
}
