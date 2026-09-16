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

/// Wraps a routed page in Kiosk mode only. Resets its idle timer on any
/// tap AND on any OrderFlowController change (so a hardware barcode
/// scanner typing into a focused field — which fires no pointer event —
/// still counts as activity, since a scan always triggers a controller
/// notification). After [idleWarningAfter] of no activity, shows an "Are
/// you still there?" dialog with its own countdown; letting that expire
/// resets the flow and returns to Landing. Never instantiated for
/// Normal/Shopping — see app_router.dart, this only wraps kiosk-mode pages.
class KioskIdleGuard extends StatefulWidget {
  final Widget child;
  final bool afterInvoice;

  const KioskIdleGuard({super.key, required this.child, this.afterInvoice = false});

  @override
  State<KioskIdleGuard> createState() => _KioskIdleGuardState();
}

class _KioskIdleGuardState extends State<KioskIdleGuard> {
  Timer? _idleTimer;
  bool _warningShowing = false;
  late final OrderFlowController _flow;

  // Signals the open _StillThereSheet to dismiss itself on activity. NOT a
  // direct Navigator.pop() call from here anymore — see _StillThereSheet's
  // own doc comment for why: a tap arriving right as the countdown expires
  // could otherwise race two independent pop() calls against the same
  // route, and if the ticker's pop wins first, a second pop (from a tap
  // whose event was already queued) would land on whatever route is now on
  // top — the actual screen underneath, not the already-closed sheet. The
  // sheet is now the single owner of its own pop; this just pings it.
  final ValueNotifier<bool> _dismissPing = ValueNotifier(false);

  _IdleContext get _ctx =>
      widget.afterInvoice ? _IdleContext.afterInvoice : _IdleContext.beforeInvoice;

  // Once the order is paid, _KioskPaidDialog owns the countdown. The idle
  // guard must not interfere with it — and must not interfere with a
  // still-open payment dialog either (terminal/QR), which can sit
  // unresolved for a long time waiting on hardware or a customer's phone.
  // See OrderFlowController.paymentInProgress.
  bool get _isPaid => _flow.order?.status == 'PAID';
  bool get _isSuspended => _isPaid || _flow.paymentInProgress;

  // Off by default (Settings → Kiosk Timers → "Enable Idle Timers"). Inactivity-
  // driven redirects have been the repeated source of Navigator-corruption
  // crashes on real hardware — with this off, the guard never starts its
  // own timer or forces navigation on any screen; only the always-on
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
    _startIdleTimer();
  }

  @override
  void dispose() {
    _flow.removeListener(_onActivity);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _idleTimer?.cancel();
    _dismissPing.dispose();
    super.dispose();
  }

  // HID barcode scanner generates key events, not pointer events.
  // Return false to not consume the event — just observe it.
  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) _onActivity();
    return false;
  }

  void _onActivity() {
    if (_warningShowing) {
      // A pointer tap can't reach here — the warning's modal barrier
      // absorbs it — but a hardware scanner's keystrokes (_onKeyEvent) and
      // the resulting OrderFlowController notification both bypass hit-
      // testing entirely. A scan while the warning is up is unambiguous
      // proof the customer is present: dismiss it the same as tapping
      // Continue, instead of silently ignoring the activity. Ping rather
      // than popping directly — see _dismissPing's doc comment above.
      _dismissPing.value = !_dismissPing.value;
      return;
    }
    if (_isSuspended) {
      _idleTimer?.cancel();
      return;
    }
    _startIdleTimer();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    if (!_timersEnabled) return;
    _idleTimer = Timer(_warnAfter, _showWarning);
  }

  Future<void> _showWarning() async {
    if (!mounted || _warningShowing) return;
    if (_isSuspended || !_timersEnabled) {
      _idleTimer?.cancel();
      return;
    }
    TraceLog.log('KioskIdleGuard(${_ctx.name}): idle timer fired, showing warning');
    setState(() => _warningShowing = true);

    // A modal bottom sheet, not a centered dialog — same blocking behavior
    // (isDismissible/enableDrag both off, so it only closes via its own
    // buttons, a timeout, or _onActivity's programmatic pop above), just
    // anchored to the bottom to match the paid-invoice countdown's look.
    final continued = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StillThereSheet(context: _ctx, dismissPing: _dismissPing),
    );

    TraceLog.log('KioskIdleGuard(${_ctx.name}): sheet resolved, continued=$continued');
    if (!mounted) return;
    setState(() => _warningShowing = false);

    if (continued == true) {
      _startIdleTimer();
    } else {
      // Expired, or customer explicitly chose "Start New Order" — same
      // action either way: reset and go Home. No previous-customer state
      // should carry into whatever loads next.
      _flow.reset();
      if (!mounted) return;
      final nav = Navigator.of(context);
      // pushNamedAndRemoveUntil with (route)=>false removes ALL routes before
      // pushing the new one. If we are already at the root (canPop==false),
      // Flutter's history is a single entry and removing it triggers the
      // '_history.isNotEmpty' assertion. Skip navigation — we're already home.
      if (nav.canPop()) {
        TraceLog.log('KioskIdleGuard(${_ctx.name}): redirecting to landing');
        nav.pushNamedAndRemoveUntil(Routes.landing, (route) => false);
        TraceLog.log('KioskIdleGuard(${_ctx.name}): redirect call returned');
      } else {
        TraceLog.log('KioskIdleGuard(${_ctx.name}): already at root, skipped redirect');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onActivity(),
      onPointerMove: (_) => _onActivity(),
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
