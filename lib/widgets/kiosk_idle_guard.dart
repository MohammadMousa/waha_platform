import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
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

  _IdleContext get _ctx =>
      widget.afterInvoice ? _IdleContext.afterInvoice : _IdleContext.beforeInvoice;

  // Once the order is paid, _KioskPaidDialog owns the countdown.
  // The idle guard must not interfere with it.
  bool get _isPaid => _flow.order?.status == 'PAID';

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
      // Continue, instead of silently ignoring the activity.
      Navigator.of(context).pop(true);
      return;
    }
    if (_isPaid) {
      _idleTimer?.cancel();
      return;
    }
    _startIdleTimer();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_warnAfter, _showWarning);
  }

  Future<void> _showWarning() async {
    if (!mounted || _warningShowing) return;
    if (_isPaid) {
      _idleTimer?.cancel();
      return;
    }
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
      builder: (_) => _StillThereSheet(context: _ctx),
    );

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
        nav.pushNamedAndRemoveUntil(Routes.landing, (route) => false);
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
  const _StillThereSheet({required this.context});

  @override
  State<_StillThereSheet> createState() => _StillThereSheetState();
}

class _StillThereSheetState extends State<_StillThereSheet> {
  late int _secondsLeft;
  Timer? _ticker;

  Duration get _countdown => widget.context == _IdleContext.afterInvoice
      ? kioskTimerConfig.afterInvoiceWarningCountdown
      : kioskTimerConfig.beforeInvoiceWarningCountdown;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _countdown.inSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _ticker?.cancel();
        Navigator.of(context).pop(false); // expired
      }
    });
  }

  @override
  void dispose() {
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
      onPrimary: () => Navigator.of(context).pop(true),
      secondaryLabel: l10n.kioskIdleNewOrder,
      onSecondary: () => Navigator.of(context).pop(false),
    );
  }
}
