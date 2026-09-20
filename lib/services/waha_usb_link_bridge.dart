import 'dart:async';

import 'package:flutter/services.dart';

import 'trace_log.dart';

/// Push events from the native WahaUsbHost (scanning, permissionRequested,
/// aoaStarted, usbConnected, ready, usbDisconnected, error). [code] carries a
/// distinct error code when state == 'error'.
class WahaLinkEvent {
  final String state;
  final String? code;
  final String? description;
  const WahaLinkEvent(this.state, {this.code, this.description});
}

/// Outcome of connect() / requestPayment(). Native never throws across the
/// channel — every failure comes back as ok == false with a distinct
/// [errorCode] (see WahaLinkProtocol.kt ErrorCode and WahaUsbHost.kt
/// HostError), so callers can show the real reason instead of a generic one.
class WahaLinkResult {
  final bool ok;
  final String? status; // approved | declined | error | cancelled
  final String? errorCode;
  final String? message;
  final String? approvalCode;
  final Map<String, dynamic> details;

  const WahaLinkResult({
    required this.ok,
    this.status,
    this.errorCode,
    this.message,
    this.approvalCode,
    this.details = const {},
  });

  bool get approved => ok && status == 'approved' && approvalCode != null;

  factory WahaLinkResult.fromMap(Map? map) {
    if (map == null) {
      return const WahaLinkResult(ok: false, errorCode: 'NO_RESPONSE', message: 'No response from native link');
    }
    final details = map['details'];
    return WahaLinkResult(
      ok: map['ok'] == true,
      status: map['status'] as String?,
      errorCode: map['errorCode'] as String?,
      message: map['message'] as String?,
      approvalCode: map['approvalCode'] as String?,
      details: details is Map ? Map<String, dynamic>.from(details) : const {},
    );
  }

  String get describe =>
      errorCode == null ? (message ?? 'Failed') : '$errorCode${message == null ? '' : ' — $message'}';
}

/// Kiosk side (USB host) of the generic Waha kiosk <-> Waha Terminal link.
/// Deliberately separate from GeideaTerminalBridge — its own channels, its
/// own native host, nothing shared with the Geidea integration. Internal /
/// test transport, off unless LocalPrefs.wahaPosUsbEnabled.
class WahaUsbLinkBridge {
  WahaUsbLinkBridge._();
  static final WahaUsbLinkBridge instance = WahaUsbLinkBridge._();

  static const _method = MethodChannel('com.waha/wahalink');
  static const _events = EventChannel('com.waha/wahalink/events');

  StreamSubscription<WahaLinkEvent>? _logSub;
  Stream<WahaLinkEvent>? _stream;

  Stream<WahaLinkEvent> get events => _stream ??= _events.receiveBroadcastStream().map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return WahaLinkEvent(
          m['state'] as String? ?? 'unknown',
          code: m['code'] as String?,
          description: m['description'] as String?,
        );
      }).asBroadcastStream();

  /// Registers the native receivers and starts persisting link events to the
  /// trace log. Does NOT touch USB — that only happens on connect().
  Future<void> start() async {
    _logSub ??= events.listen((e) {
      TraceLog.log('WahaLink: ${e.state}${e.code == null ? '' : ' [${e.code}]'}'
          '${e.description == null ? '' : ' — ${e.description}'}');
    });
    try {
      await _method.invokeMethod('start');
    } on PlatformException catch (e) {
      TraceLog.log('WahaLink: start failed: ${e.message}');
    }
  }

  Future<void> stop() async {
    await _logSub?.cancel();
    _logSub = null;
    try {
      await _method.invokeMethod('stop');
    } on PlatformException {
      // Best effort.
    }
  }

  Future<bool> isConnected() async {
    try {
      return (await _method.invokeMethod<bool>('isConnected')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Always a fresh connect: the native side tears down whatever was open,
  /// does the AOA handshake if needed, and completes the hello exchange
  /// before returning. Same reason as Geidea's always-reconnect-before-payment.
  Future<WahaLinkResult> connect() async {
    try {
      return WahaLinkResult.fromMap(await _method.invokeMethod<Map>('connect'));
    } on PlatformException catch (e) {
      return WahaLinkResult(ok: false, errorCode: 'PLATFORM_ERROR', message: e.message);
    }
  }

  /// [amount] in major currency units; native formats it as the protocol's
  /// decimal string. The kiosk owns the timeout: on expiry native sends cancel
  /// and returns TIMEOUT (or the approval, if the card was charged in time).
  Future<WahaLinkResult> requestPayment({
    required String reference,
    required double amount,
    required String currency,
    required Duration timeout,
  }) async {
    try {
      return WahaLinkResult.fromMap(await _method.invokeMethod<Map>('requestPayment', {
        'reference': reference,
        'amount': amount,
        'currency': currency,
        'timeoutMs': timeout.inMilliseconds,
      }));
    } on PlatformException catch (e) {
      return WahaLinkResult(ok: false, errorCode: 'PLATFORM_ERROR', message: e.message);
    }
  }

  Future<void> cancel(String reference) async {
    try {
      await _method.invokeMethod('cancel', {'reference': reference});
    } on PlatformException {
      // Best effort.
    }
  }
}
