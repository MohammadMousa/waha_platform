import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/simulator_service.dart';
import 'app_messenger.dart';
import 'geidea_terminal_bridge.dart';
import 'trace_log.dart';
import 'waha_usb_link_bridge.dart';

/// Surfaces every Geidea USB connection event (scanning, found, lost,
/// failed) as a debug log always, and as a SnackBar toast too when the
/// simulator dev-tools panel is switched on — so plugging/unplugging the
/// terminal, or a payment's own on-demand detect attempt, is visible
/// instead of silent, without cluttering normal kiosk use when dev tools
/// are off (the default).
///
/// Mount once, above MaterialApp, for the app's whole lifetime — not
/// per-screen, so it keeps logging regardless of which route is on top.
class GeideaUsbActivityLogger extends StatefulWidget {
  final Widget child;
  const GeideaUsbActivityLogger({required this.child, super.key});

  @override
  State<GeideaUsbActivityLogger> createState() => _GeideaUsbActivityLoggerState();
}

class _GeideaUsbActivityLoggerState extends State<GeideaUsbActivityLogger> {
  StreamSubscription<GeideaConnectionEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = GeideaTerminalBridge.instance.connectionEvents.listen(_onEvent);
  }

  void _onEvent(GeideaConnectionEvent event) {
    final message = _describe(event);
    debugPrint('[GeideaUSB] $message');
    // Previously only went to debugPrint (live adb/flutter-run only) or a
    // toast (visible but never recorded) — neither survives to be read
    // after the fact. This is exactly the sequence needed to tell "cached
    // connected flag was stale" apart from "genuinely never connected" the
    // next time a payment fails with the terminal never receiving
    // anything — see _run()'s comment in invoice_screen.dart.
    TraceLog.log('GeideaUSB: $message');
    // Passive: records every attached USB device and which one the Geidea SDK
    // would pick, next to the Geidea event that triggered it (attach, retry,
    // payment start, failure). Read-only, changes nothing about Geidea.
    unawaited(WahaUsbLinkBridge.instance.usbInventory(reason: 'geidea:${event.state.name}'));

    final devToolsOn = !context.read<SimulatorService>().devToolsHidden;
    if (!devToolsOn) return;

    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('USB terminal: $message'),
        duration: const Duration(seconds: 3),
        backgroundColor: _colorFor(event.state),
      ),
    );
  }

  String _describe(GeideaConnectionEvent event) {
    switch (event.state) {
      case GeideaConnectionState.scanning:
        return event.errorDescription ?? 'Scanning for terminal...';
      case GeideaConnectionState.usbConnected:
        return 'Terminal found';
      case GeideaConnectionState.usbDisconnected:
        return 'Terminal disconnected';
      case GeideaConnectionState.error:
        return 'Failed — ${event.errorDescription ?? "unknown error"}';
      case GeideaConnectionState.serviceConnected:
        return 'USB service ready';
      case GeideaConnectionState.unknown:
        return 'Unknown USB event';
    }
  }

  Color _colorFor(GeideaConnectionState state) {
    switch (state) {
      case GeideaConnectionState.usbConnected:
        return Colors.green.shade700;
      case GeideaConnectionState.usbDisconnected:
      case GeideaConnectionState.error:
        return Colors.red.shade700;
      case GeideaConnectionState.scanning:
      case GeideaConnectionState.serviceConnected:
      case GeideaConnectionState.unknown:
        return Colors.blueGrey.shade700;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
