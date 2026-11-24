import 'dart:ui' show FrameTiming;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'trace_log.dart';

/// Counters for the log: how smooth the screen is, how long the local database
/// and the sync pulls take, how many sounds were played. Counters only — no
/// line per event, no timer.
///
/// Everything is measured ONLY while logging is on (the local Settings switch
/// or the server property `enable_logging`): [setEnabled] is called from
/// [TraceLog.setEnabled], the one place that state passes through. With
/// logging off nothing is registered and every `record…` call returns at once.
///
/// The numbers leave the app in three ways: the native upload asks for them
/// just before it builds a report (`perfSnapshot`, answered by [install]);
/// they are handed over to the native side at the end of a payment, of a sync
/// pull and at a heartbeat ([push]), as the fallback when the app is too busy
/// to answer; and one line is written to the log before a scheduled restart.
class PerfStats {
  PerfStats._();
  static final PerfStats instance = PerfStats._();

  static const _channel = MethodChannel('com.waha/geidea');

  bool _enabled = false;
  bool get enabled => _enabled;

  DateTime _since = DateTime.now();

  // Frames.
  int frames = 0;
  int framesOver100 = 0;
  int framesOver700 = 0;
  int worstFrameMs = 0;
  int _buildMsSum = 0;
  int _rasterMsSum = 0;

  // Local database.
  int dbReads = 0;
  int dbWrites = 0;
  int dbSlow = 0;
  int dbMaxMs = 0;
  int _dbMsSum = 0;

  // Sync pulls.
  int pullsAttempted = 0;
  int pullsCompleted = 0;
  int pullsFailed = 0;
  int pullsPaused = 0;
  int pullsZeroRow = 0;
  int pullRows = 0;
  int pullRetries = 0;
  int pullLongestMs = 0;
  DateTime? lastPullOkAt;

  // Sounds.
  int sounds = 0;

  /// Turns the measuring on or off. Counters start from zero each time it is
  /// turned on, and are dropped when it is turned off.
  void setEnabled(bool on) {
    if (on == _enabled) return;
    _enabled = on;
    if (on) {
      reset();
      try {
        WidgetsFlutterBinding.ensureInitialized();
        WidgetsBinding.instance.addTimingsCallback(_onTimings);
      } catch (_) {}
    } else {
      try {
        WidgetsBinding.instance.removeTimingsCallback(_onTimings);
      } catch (_) {}
      reset();
    }
  }

  @visibleForTesting
  void reset() {
    _since = DateTime.now();
    frames = framesOver100 = framesOver700 = worstFrameMs = 0;
    _buildMsSum = _rasterMsSum = 0;
    dbReads = dbWrites = dbSlow = dbMaxMs = _dbMsSum = 0;
    pullsAttempted = pullsCompleted = pullsFailed = pullsPaused = pullsZeroRow = 0;
    pullRows = pullLongestMs = pullRetries = 0;
    lastPullOkAt = null;
    sounds = 0;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      recordFrame(
        total: t.totalSpan,
        build: t.buildDuration,
        raster: t.rasterDuration,
      );
    }
  }

  void recordFrame({
    required Duration total,
    required Duration build,
    required Duration raster,
  }) {
    if (!_enabled) return;
    final ms = total.inMilliseconds;
    frames++;
    if (ms > 100) framesOver100++;
    if (ms > 700) framesOver700++;
    if (ms > worstFrameMs) worstFrameMs = ms;
    _buildMsSum += build.inMilliseconds;
    _rasterMsSum += raster.inMilliseconds;
  }

  void recordDb(Duration took, {required bool write}) {
    if (!_enabled) return;
    if (write) {
      dbWrites++;
    } else {
      dbReads++;
    }
    final ms = took.inMilliseconds;
    _dbMsSum += ms;
    if (ms > 100) dbSlow++;
    if (ms > dbMaxMs) dbMaxMs = ms;
  }

  /// One finished pull attempt. [paused]: stopped because a customer was
  /// using the screen. [failed]: stopped by an error.
  void recordPull({
    required Duration took,
    required int rows,
    bool paused = false,
    bool failed = false,
  }) {
    if (!_enabled) return;
    pullsAttempted++;
    if (paused) {
      pullsPaused++;
    } else if (failed) {
      pullsFailed++;
    } else {
      pullsCompleted++;
      pullRows += rows;
      if (rows == 0) pullsZeroRow++;
      lastPullOkAt = DateTime.now();
    }
    if (took.inMilliseconds > pullLongestMs) pullLongestMs = took.inMilliseconds;
  }

  /// A pull request repeated on a new connection.
  void recordPullRetry() {
    if (!_enabled) return;
    pullRetries++;
  }

  void recordSound() {
    if (!_enabled) return;
    sounds++;
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _avg(int sum, int n) => n == 0 ? '-' : (sum / n).toStringAsFixed(1);

  /// One line with every counter, or 'off' when logging is off.
  String snapshot({DateTime? now}) {
    if (!_enabled) return 'off (logging is off, nothing is measured)';
    final n = now ?? DateTime.now();
    final mins = n.difference(_since).inMinutes;
    final dbN = dbReads + dbWrites;
    return 'counted since ${_clock(_since)} ($mins min) | '
        'screen: frames=$frames over100ms=$framesOver100 over700ms=$framesOver700 '
        'worst=${worstFrameMs}ms avgBuild=${_avg(_buildMsSum, frames)}ms avgDraw=${_avg(_rasterMsSum, frames)}ms | '
        'database: reads=$dbReads writes=$dbWrites avg=${_avg(_dbMsSum, dbN)}ms max=${dbMaxMs}ms over100ms=$dbSlow | '
        'sync: attempted=$pullsAttempted completed=$pullsCompleted failed=$pullsFailed paused=$pullsPaused '
        'zeroRow=$pullsZeroRow rows=$pullRows retries=$pullRetries longest=${(pullLongestMs / 1000).toStringAsFixed(1)}s '
        'lastOk=${lastPullOkAt == null ? "none" : _clock(lastPullOkAt!)} | '
        'sounds=$sounds';
  }

  /// Hands the counters to the native side (end of a payment, end of a sync
  /// pull, heartbeat). Never throws; does nothing while logging is off.
  Future<void> push() async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod('perfPush', {'text': snapshot()});
    } catch (_) {}
  }

  /// Answers the native upload's request for a fresh snapshot. Call once at
  /// startup, after the binding exists.
  void install() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'perfSnapshot') return snapshot();
      return null;
    });
  }

  /// One line in the log before a scheduled restart: how the app was doing at
  /// the end of its run (a baseline that needs no incident).
  Future<void> logAtRestart() async {
    if (!_enabled) return;
    var native = '';
    try {
      native = await _channel.invokeMethod<String>('perfNative') ?? '';
    } catch (_) {}
    TraceLog.log('PERF at restart: ${snapshot()}${native.isEmpty ? '' : ' | tablet/app: $native'}');
  }
}
