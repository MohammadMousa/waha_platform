import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/app_router.dart';
import '../state/browsing_mode_service.dart';
import '../state/order_flow_controller.dart';

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

  Duration get _warnAfter => _ctx == _IdleContext.afterInvoice
      ? kioskTimerConfig.afterInvoiceIdleWarningAfter
      : kioskTimerConfig.beforeInvoiceIdleWarningAfter;

  @override
  void initState() {
    super.initState();
    _flow = context.read<OrderFlowController>();
    _flow.addListener(_onActivity);
    _startIdleTimer();
  }

  @override
  void dispose() {
    _flow.removeListener(_onActivity);
    _idleTimer?.cancel();
    super.dispose();
  }

  void _onActivity() {
    if (_warningShowing) return; // don't silently swallow the warning
    _startIdleTimer();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_warnAfter, _showWarning);
  }

  Future<void> _showWarning() async {
    if (!mounted || _warningShowing) return;
    setState(() => _warningShowing = true);

    final continued = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StillThereDialog(context: _ctx),
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
      Navigator.of(context)
          .pushNamedAndRemoveUntil(Routes.landing, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onActivity(),
      child: widget.child,
    );
  }
}

class _StillThereDialog extends StatefulWidget {
  final _IdleContext context;
  const _StillThereDialog({required this.context});

  @override
  State<_StillThereDialog> createState() => _StillThereDialogState();
}

class _StillThereDialogState extends State<_StillThereDialog> {
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
    final isAfter = widget.context == _IdleContext.afterInvoice;
    return AlertDialog(
      title: const Text('Are you still there?'),
      content: Text(
        isAfter
            ? 'This screen will close in $_secondsLeft seconds.'
            : 'Your session will reset in $_secondsLeft seconds.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Start New Order'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
