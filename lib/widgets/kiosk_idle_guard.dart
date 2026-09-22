import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../services/local_prefs.dart';
import '../services/trace_log.dart';
import '../state/browsing_mode_service.dart';
import '../state/order_flow_controller.dart';
import 'timer_footer_sheet.dart';

enum _IdleContext { beforeInvoice, afterInvoice }

/// Single, app-wide idle-timer owner for Kiosk mode. Mounted exactly ONCE,
/// wrapping MaterialApp (see main.dart) — NOT per-route. Tracks which
/// route is currently on top via [KioskRouteObserver] and acts through
/// [navigatorKey] (both in app_router.dart) instead of a route's own
/// BuildContext, so it doesn't depend on any specific pushed route still
/// being mounted.
///
/// Replaces an earlier per-route design where onGenerateRoute wrapped every
/// guarded page in its own KioskIdleGuard instance — see app_router.dart's
/// comment on why that could run two independent timers at once and caused
/// a real black-screen crash. There is exactly one Timer and one "warning
/// showing" flag in the whole app now, so that race is structurally
/// impossible regardless of how many guarded routes are stacked
/// underneath each other.
class KioskIdleGuard extends StatefulWidget {
  final Widget child;
  const KioskIdleGuard({required this.child, super.key});

  @override
  State<KioskIdleGuard> createState() => _KioskIdleGuardState();
}

class _KioskIdleGuardState extends State<KioskIdleGuard> {
  Timer? _idleTimer;
  bool _warningShowing = false;
  late final OrderFlowController _flow;
  String? _routeName;

  // Signals the open _StillThereSheet to dismiss itself on activity — see
  // _StillThereSheet's own doc comment for why this is a ping, not a
  // direct Navigator.pop() call from here.
  final ValueNotifier<bool> _dismissPing = ValueNotifier(false);

  bool get _isGuardedRoute =>
      browsingModeService.mode == BrowsingMode.kiosk &&
      _routeName != null &&
      _routeName != Routes.landing &&
      Routes.kioskAllowlist.contains(_routeName);

  _IdleContext get _ctx => Routes.afterInvoiceRoutes.contains(_routeName)
      ? _IdleContext.afterInvoice
      : _IdleContext.beforeInvoice;

  // Once the order is paid, _KioskPaidDialog owns the countdown. The idle
  // guard must not interfere with it — and must not interfere with a
  // still-open payment dialog either (terminal/QR), which can sit
  // unresolved for a long time waiting on hardware or a customer's phone.
  // See OrderFlowController.paymentInProgress.
  bool get _isPaid => _flow.order?.status == 'PAID';
  bool get _isSuspended => _isPaid || _flow.paymentInProgress;

  // Off by default (Settings → Kiosk Timers → "Enable Idle Timers"). With
  // this off, no timer is ever started on any screen; only the always-on
  // post-payment redirect in _KioskPaidDialog still fires, since a paid
  // screen can't be left up forever regardless of this setting.
  bool get _timersEnabled => LocalPrefs.kioskTimersEnabled;

  Duration get _warnAfter => _ctx == _IdleContext.afterInvoice
      ? kioskTimerConfig.afterInvoiceIdleWarningAfter
      : kioskTimerConfig.beforeInvoiceIdleWarningAfter;

  @override
  void initState() {
    super.initState();
    _flow = context.read<OrderFlowController>();
    _flow.addListener(_onActivity);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    KioskRouteObserver.currentRouteName.addListener(_onRouteChanged);
    _routeName = KioskRouteObserver.currentRouteName.value;
  }

  @override
  void dispose() {
    _flow.removeListener(_onActivity);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    KioskRouteObserver.currentRouteName.removeListener(_onRouteChanged);
    _idleTimer?.cancel();
    _dismissPing.dispose();
    super.dispose();
  }

  void _onRouteChanged() {
    _routeName = KioskRouteObserver.currentRouteName.value;
    if (_warningShowing) {
      // Navigated away while a warning sheet was up (shouldn't normally
      // happen — the sheet is modal — but stay safe rather than let a
      // stale timer/sheet act against whatever's now on top).
      _dismissPing.value = !_dismissPing.value;
    }
    // Arriving at a new screen counts as activity, and also re-evaluates
    // whether the new top route is even guarded.
    _maybeRestartTimer();
  }

  // HID barcode scanner generates key events, not pointer events.
  // Return false to not consume the event — just observe it.
  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) _onActivity();
    return false;
  }

  void _onActivity() {
    if (_warningShowing) {
      // Only NON-pointer activity gets here while the warning is up (see
      // build(): pointer events are ignored then): a hardware scanner's
      // keystrokes (_onKeyEvent) and the resulting OrderFlowController
      // notification bypass hit-testing entirely. A scan while the warning is
      // up is unambiguous proof the customer is present: dismiss it the same
      // as tapping Continue, instead of silently ignoring the activity.
      _dismissPing.value = !_dismissPing.value;
      return;
    }
    _maybeRestartTimer();
  }

  void _maybeRestartTimer() {
    _idleTimer?.cancel();
    if (!_isGuardedRoute || _isSuspended || !_timersEnabled) return;
    _idleTimer = Timer(_warnAfter, _showWarning);
  }

  Future<void> _showWarning() async {
    if (_warningShowing || !_isGuardedRoute || _isSuspended || !_timersEnabled) return;
    final navContext = navigatorKey.currentContext;
    if (navContext == null) return;
    TraceLog.log('KioskIdleGuard(${_ctx.name}): idle timer fired, showing warning');
    _warningShowing = true;

    // A modal bottom sheet, not a centered dialog — same blocking behavior
    // (isDismissible/enableDrag both off, so it only closes via its own
    // buttons, a timeout, or _onActivity's programmatic pop above), just
    // anchored to the bottom to match the paid-invoice countdown's look.
    final continued = await showModalBottomSheet<bool>(
      context: navContext,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StillThereSheet(context: _ctx, dismissPing: _dismissPing),
    );

    TraceLog.log('KioskIdleGuard(${_ctx.name}): sheet resolved, continued=$continued');
    _warningShowing = false;
    if (!mounted) return;

    if (continued == true) {
      _maybeRestartTimer();
    } else {
      // Expired, or customer explicitly chose "Start New Order" — same
      // action either way: reset and go Home, unconditionally, regardless
      // of cart contents. goHomeKeepingLanding pops back to the existing
      // root Landing (keeping its WebView alive, so no blank screen) and
      // only rebuilds Landing if the root somehow isn't Landing.
      _flow.reset();
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      TraceLog.log('KioskIdleGuard(${_ctx.name}): redirecting to landing');
      goHomeKeepingLanding(nav);
      TraceLog.log('KioskIdleGuard(${_ctx.name}): redirect call returned');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      // Ignore pointer events while the warning sheet is open. The sheet is
      // INSIDE this Listener's subtree, so a finger-down on its "Start New
      // Order" button used to reach _onActivity() first, which dismissed the
      // sheet as "Continue" (the ping below) before the button's own onPressed
      // (fired on release) could run — New Order just hid the timer. The
      // sheet handles its own taps; the modal barrier is not dismissible.
      onPointerDown: (_) { if (!_warningShowing) _onActivity(); },
      onPointerMove: (_) { if (!_warningShowing) _onActivity(); },
      child: widget.child,
    );
  }
}

class _StillThereSheet extends StatefulWidget {
  final _IdleContext context;
  final ValueNotifier<bool> dismissPing;
  const _StillThereSheet({required this.context, required this.dismissPing});

  @override
  State<_StillThereSheet> createState() => _StillThereSheetState();
}

class _StillThereSheetState extends State<_StillThereSheet> {
  late int _secondsLeft;
  Timer? _ticker;

  // Four independent triggers can each want to close this sheet: the
  // ticker expiring, the parent's dismissPing (activity while showing),
  // and the two buttons below. Without a single-owner guard, two of them
  // landing close together could each call Navigator.pop() on what they
  // each still believe is this sheet's route — if the first pop already
  // resolved and closed it, the second would land on whatever route is
  // now on top instead, i.e. the real screen underneath. _resolve() makes
  // whichever trigger fires first the only one that can ever actually
  // pop; every later call is a no-op.
  bool _settled = false;

  Duration get _countdown => widget.context == _IdleContext.afterInvoice
      ? kioskTimerConfig.afterInvoiceWarningCountdown
      : kioskTimerConfig.beforeInvoiceWarningCountdown;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _countdown.inSeconds;
    widget.dismissPing.addListener(_onDismissPing);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) _resolve(false); // expired
    });
  }

  void _onDismissPing() => _resolve(true);

  void _resolve(bool value) {
    if (_settled || !mounted) return;
    _settled = true;
    _ticker?.cancel();
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    widget.dismissPing.removeListener(_onDismissPing);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final isAfter = widget.context == _IdleContext.afterInvoice;
    return TimerFooterSheet(
      title: l10n.kioskIdleTitle,
      message: isAfter
          ? l10n.kioskIdleAfterBody(_secondsLeft)
          : l10n.kioskIdleBeforeBody(_secondsLeft),
      secondsLeft: _secondsLeft,
      primaryLabel: l10n.kioskIdleContinue,
      primaryColor: scheme.primary,
      onPrimary: () => _resolve(true),
      secondaryLabel: l10n.kioskIdleNewOrder,
      onSecondary: () => _resolve(false),
    );
  }
}
