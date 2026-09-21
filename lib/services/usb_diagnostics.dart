import 'dart:async';

import 'package:flutter/services.dart';

import 'local_prefs.dart';

/// Read-only USB snapshot: every attached device, which one Geidea's SDK
/// would pick, and whether this device is acting as a USB host or peripheral.
/// Never opens, claims or requests permission for anything, so it cannot
/// change how the Geidea integration behaves.
class UsbDiagnostics {
  UsbDiagnostics._();

  static const _channel = MethodChannel('com.waha/usbdiag');

  /// Returns the report text. With [reason] it is also written to the trace
  /// log. Never throws — a missing native side comes back as text.
  static Future<String> inventory({String? reason}) async {
    try {
      return (await _channel.invokeMethod<String>('inventory', {'reason': reason})) ?? '';
    } catch (e) {
      return 'USB inventory failed: $e';
    }
  }

  /// Fire-and-forget snapshot for the trace log, taken only while trace
  /// logging is on — with it off, nothing runs at all.
  static void logSnapshot(String reason) {
    if (!LocalPrefs.loggingEnabled) return;
    unawaited(inventory(reason: reason));
  }
}
