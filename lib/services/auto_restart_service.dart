import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../state/browsing_mode_service.dart';
import '../state/order_flow_controller.dart';
import '../widgets/timer_footer_sheet.dart';
import 'geidea_terminal_bridge.dart';
import 'local_prefs.dart';
import 'trace_log.dart';

enum RestartDecision { idle, waiting, countdown }

/// When to restart, as pure logic (unit-tested; the service below drives it).
///
/// Time is the app's own uptime (a stopwatch since the process started), never
/// the wall clock, so a corrected or wrong tablet clock cannot trigger or
/// block a restart. A restart is due once the uptime reaches the period. If
/// the kiosk is busy at that moment (not on the landing screen, or the cart
/// is not empty, or a payment is under way) it waits [wait] (property
/// `device_auto_restart_wait_minutes`, default 3 minutes) and asks again, as
/// often as needed; "Not now" waits the same. Never in the first [minUptime],
/// so a faulty setting cannot make it restart in a loop.
class AutoRestartPlanner {
  AutoRestartPlanner({
    required Duration period,
    Duration wait = const Duration(minutes: 3),
    this.minUptime = const Duration(minutes: 10),
  })  : _period = period,
        _wait = wait,
        _nextDue = period;

  Duration _period;
  Duration _wait;
  Duration _nextDue;
  final Duration minUptime;

  Duration get period => _period;
  Duration get wait => _wait;
  Duration get nextDue => _nextDue;

  void setWait(Duration w) => _wait = w;

  void setPeriod(Duration p) {
    if (p == _period) return;
    _period = p;
    _nextDue = p;
  }

  RestartDecision check({
    required Duration uptime,
    required bool enabled,
    required bool canRestartNow,
  }) {
    if (!enabled || uptime < minUptime || uptime < _nextDue) return RestartDecision.idle;
    if (!canRestartNow) {
      _nextDue = uptime + _wait;
      return RestartDecision.waiting;
    }
    return RestartDecision.countdown;
  }

  /// The customer pressed "Not now", or the kiosk became busy during the countdown.
  void snoozed(Duration uptime) => _nextDue = uptime + _wait;
}

/// Restarts the kiosk app on a schedule (server properties
/// `device_auto_restart_enabled`, `device_auto_restart_hours`, default 2, and
/// `device_auto_restart_wait_minutes`, default 3): a restart gives the Geidea SDK, the USB connection and the app
/// a clean start, which is what has cleared every terminal outage seen so far.
/// It restarts only while the kiosk is idle on the landing screen with an empty
/// cart, and shows a countdown footer first.
class AutoRestartService {
  AutoRestartService._();
  static final AutoRestartService instance = AutoRestartService._();

  static const defaultPeriodHours = 2.0;
  static const minPeriodHours = 0.25; // 15 minutes
  static const maxPeriodHours = 168.0; // a week
  static const defaultWaitMinutes = 3;
  static const minWaitMinutes = 1;
  static const maxWaitMinutes = 60;
  static const countdownSeconds = 10;
  static const _channel = MethodChannel('com.waha/geidea');

  final Stopwatch _uptime = Stopwatch()..start();
  late final AutoRestartPlanner _planner =
      AutoRestartPlanner(period: _periodFromPrefs(), wait: _waitFromPrefs());
  Timer? _timer;
  bool _flowRunning = false;
  bool _loggedWaiting = false;

  /// `device_auto_restart_hours`: hours, decimals allowed. Anything unusable
  /// falls back to the default; the rest is kept inside sane limits.
  static double parsePeriodHours(String? raw) {
    final v = double.tryParse((raw ?? '').trim());
    if (v == null || v.isNaN || v.isInfinite || v <= 0) return defaultPeriodHours;
    return v.clamp(minPeriodHours, maxPeriodHours).toDouble();
  }

  /// `device_auto_restart_wait_minutes`: whole minutes; unusable values fall
  /// back to the default, the rest is kept between 1 and 60.
  static int parseWaitMinutes(String? raw) {
    final v = int.tryParse((raw ?? '').trim());
    if (v == null || v <= 0) return defaultWaitMinutes;
    return v.clamp(minWaitMinutes, maxWaitMinutes);
  }

  static Duration _periodFromPrefs() =>
      Duration(minutes: (LocalPrefs.autoRestartPeriodHours * 60).round());
  static Duration _waitFromPrefs() => Duration(minutes: LocalPrefs.autoRestartWaitMinutes);

  /// Applies the organization properties from a config the server actually
  /// returned. An empty map means the request failed and changes nothing.
  static Future<void> applyConfig(Map<String, String> config) async {
    if (config.isEmpty) return;
    final on = config['device_auto_restart_enabled']?.trim().toLowerCase() == 'true';
    final hours = parsePeriodHours(config['device_auto_restart_hours']);
    final wait = parseWaitMinutes(config['device_auto_restart_wait_minutes']);
    if (LocalPrefs.autoRestartEnabled != on) await LocalPrefs.setAutoRestartEnabled(on);
    if (LocalPrefs.autoRestartPeriodHours != hours) await LocalPrefs.setAutoRestartPeriodHours(hours);
    if (LocalPrefs.autoRestartWaitMinutes != wait) await LocalPrefs.setAutoRestartWaitMinutes(wait);
    instance._planner.setPeriod(_periodFromPrefs());
    instance._planner.setWait(_waitFromPrefs());
  }

  /// Starts the once-every-30-seconds check. Safe to call more than once.
  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  /// The idle rule, as pure logic (unit-tested): kiosk mode, the landing
  /// screen, an empty cart, no order or payment in progress and no terminal
  /// attempt still pending.
  static bool isIdle({
    required bool kioskMode,
    required bool onLanding,
    required bool cartEmpty,
    required bool noOrder,
    required bool noPayment,
    required bool noPendingAttempt,
  }) =>
      kioskMode && onLanding && cartEmpty && noOrder && noPayment && noPendingAttempt;

  /// Reads the live state. [ignoreRoute] is for the check made WHILE the
  /// countdown sheet is open: the sheet is itself the top route (the route
  /// observer reports it with no name), so the landing-screen test is only
  /// made when the countdown starts, not on every tick after.
  bool canRestartNow({bool ignoreRoute = false}) {
    try {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return false;
      final flow = ctx.read<OrderFlowController>();
      return isIdle(
        kioskMode: browsingModeService.mode == BrowsingMode.kiosk,
        onLanding: ignoreRoute || KioskRouteObserver.currentRouteName.value == Routes.landing,
        cartEmpty: flow.cart.isEmpty,
        noOrder: flow.orderId == null,
        noPayment: !flow.paymentInProgress,
        noPendingAttempt: !GeideaTerminalBridge.hasPendingAttempt,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _tick() async {
    if (_flowRunning) return;
    final d = _planner.check(
      uptime: _uptime.elapsed,
      enabled: LocalPrefs.autoRestartEnabled,
      canRestartNow: canRestartNow(),
    );
    switch (d) {
      case RestartDecision.idle:
        _loggedWaiting = false;
      case RestartDecision.waiting:
        if (!_loggedWaiting) {
          _loggedWaiting = true;
          TraceLog.log('AUTORESTART: due, but the kiosk is busy — checking again every ${_planner.wait.inMinutes} min');
        }
      case RestartDecision.countdown:
        _loggedWaiting = false;
        await _runFlow(test: false);
    }
  }

  /// Settings test button: the real countdown and restart, right now.
  Future<void> runTest() async {
    if (_flowRunning) return;
    await _runFlow(test: true);
  }

  Future<void> _runFlow({required bool test}) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    _flowRunning = true;
    try {
      TraceLog.log('AUTORESTART: ${test ? "test button" : "due and idle"} — showing the countdown');
      final go = await showModalBottomSheet<bool>(
        context: ctx,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _RestartSheet(
          seconds: countdownSeconds,
          // A scheduled restart gives way if the kiosk gets busy meanwhile.
          stillIdle: test ? null : () => canRestartNow(ignoreRoute: true),
        ),
      );
      if (go == true) {
        await restartNow(test ? 'test button' : 'scheduled auto-restart');
      } else {
        TraceLog.log('AUTORESTART: cancelled — trying again in ${_planner.wait.inMinutes} min');
        _planner.snoozed(_uptime.elapsed);
      }
    } finally {
      _flowRunning = false;
    }
  }

  Future<void> restartNow(String reason) async {
    TraceLog.log('AUTORESTART: restarting now ($reason)');
    try {
      await _channel.invokeMethod('restartApp', {'reason': reason});
    } catch (e) {
      TraceLog.log('AUTORESTART: the restart call failed: $e');
    }
  }
}

class _RestartSheet extends StatefulWidget {
  final int seconds;
  final bool Function()? stillIdle;
  const _RestartSheet({required this.seconds, this.stillIdle});

  @override
  State<_RestartSheet> createState() => _RestartSheetState();
}

class _RestartSheetState extends State<_RestartSheet> {
  late int _left = widget.seconds;
  Timer? _ticker;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.stillIdle != null && !widget.stillIdle!()) {
        _resolve(false);
        return;
      }
      setState(() => _left--);
      if (_left <= 0) _resolve(true);
    });
  }

  void _resolve(bool value) {
    if (_settled || !mounted) return;
    _settled = true;
    _ticker?.cancel();
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TimerFooterSheet(
      message: l10n.autoRestartMessage(_left),
      secondsLeft: _left,
      primaryLabel: l10n.autoRestartNotNow,
      primaryColor: Theme.of(context).colorScheme.primary,
      onPrimary: () => _resolve(false),
      secondaryLabel: l10n.autoRestartNow,
      onSecondary: () => _resolve(true),
    );
  }
}
