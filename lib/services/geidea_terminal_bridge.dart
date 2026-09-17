import 'dart:async';

import 'package:flutter/services.dart';

/// Push connection-state events from the native USBConnectionListener
/// (spec §4.2) — separate from the request/response MethodChannel below
/// since these arrive unprompted, not as a reply to a Dart-initiated call.
/// [scanning] covers every kind of "attempting a connection right now"
/// moment (startup, a USB attach broadcast, a bounded startup retry, or an
/// on-demand [GeideaTerminalBridge.detectTerminal] call) — see
/// GeideaUsbActivityLogger for where these surface as a dev-tools toast/log.
enum GeideaConnectionState {
  unknown,
  serviceConnected,
  scanning,
  usbConnected,
  usbDisconnected,
  error,
}

class GeideaConnectionEvent {
  final GeideaConnectionState state;
  final String? errorDescription;
  const GeideaConnectionEvent(this.state, {this.errorDescription});
}

/// Result of a terminal purchase attempt. `approved` mirrors the SDK's
/// response[0] ("1"/"0"). `details` is the parsed JSON transaction payload
/// (response[2] — merchantName, cardNumber, approvalCode, rrn, ...) when
/// approved; empty on decline/error. `raw` keeps the untouched native
/// response map for anything not modeled here.
class GeideaPaymentResult {
  final bool approved;
  final String? approvalCode;
  final String? rrn;
  final Map<String, dynamic> details;
  final String? errorMessage;

  const GeideaPaymentResult({
    required this.approved,
    this.approvalCode,
    this.rrn,
    this.details = const {},
    this.errorMessage,
  });
}

/// Bridge to the Geidea Android SDK (USB Serial POS terminal) via platform
/// channels. Kotlin side: MainActivity.kt. No web API involved — the SDK
/// talks to the terminal directly over USB; this only crosses the
/// Flutter/Android boundary, not the network.
class GeideaTerminalBridge {
  GeideaTerminalBridge._();
  static final GeideaTerminalBridge instance = GeideaTerminalBridge._();

  static const _methodChannel = MethodChannel('com.waha/geidea');
  static const _eventChannel = EventChannel('com.waha/geidea/events');

  /// Bypasses the native SDK/USB entirely and returns canned results, so the
  /// rest of the flow (InvoiceScreen dialog, ApiClient session calls, order
  /// confirmation) can be tested before real hardware is available. Two
  /// ways to turn this on: a build-time `--dart-define=GEIDEA_MOCK=true`
  /// (baked into the APK, can't be toggled at runtime), or the runtime
  /// "Fake Payment Terminal" switch in Settings → Developer Tools
  /// ([fakeTerminalEnabled] below). [fakeTerminalEnabled] is deliberately
  /// an in-memory field, NOT persisted to LocalPrefs — it always resets to
  /// false on a fresh app launch, so a kiosk can never be left silently
  /// faking successful payments across a restart just because someone
  /// forgot to flip it back off after testing.
  static bool fakeTerminalEnabled = false;
  static bool get _mock =>
      const bool.fromEnvironment('GEIDEA_MOCK') || fakeTerminalEnabled;

  Stream<GeideaConnectionEvent>? _connectionStream;

  /// Live push stream of USB connection state — subscribe once (e.g. at
  /// app startup in Kiosk mode) rather than per-payment-attempt, so the
  /// Kiosk can show "terminal not connected" ambiently, not just at the
  /// moment of paying.
  Stream<GeideaConnectionEvent> get connectionEvents {
    return _connectionStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      final state = GeideaConnectionState.values.firstWhere(
        (s) => s.name == map['state'],
        orElse: () => GeideaConnectionState.unknown,
      );
      return GeideaConnectionEvent(state, errorDescription: map['description'] as String?);
    }).asBroadcastStream();
  }

  Future<bool> initialize() async {
    if (_mock) return true;
    try {
      final result = await _methodChannel.invokeMethod<bool>('initializeTerminal');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> checkCommunication() async {
    if (_mock) return true;
    try {
      final result = await _methodChannel.invokeMethod<Map>('checkCommunication');
      return result?['status'] == '1' || result?['status'] == true;
    } on PlatformException {
      return false;
    }
  }

  /// [amount] in major currency units (e.g. SAR), matching `order.total`
  /// directly — no minor-unit conversion. [reference] is the Waha order id
  /// (already globally unique), passed through as `ecrReferenceNumber`.
  Future<GeideaPaymentResult> startPayment({
    required double amount,
    required String reference,
    Duration? timeout,
  }) async {
    if (_mock) {
      await Future.delayed(const Duration(seconds: 2));
      return GeideaPaymentResult(
        approved: true,
        approvalCode: '000000',
        rrn: '000000000000',
        details: {'mock': true, 'reference': reference, 'amount': amount},
      );
    }
    try {
      final future = _methodChannel.invokeMethod<Map>('startPayment', {
        'amount': amount,
        'reference': reference,
        'isPrinterEnabled': false, // kiosk has no printer
      });
      final result = timeout != null ? await future.timeout(timeout) : await future;
      if (result == null) {
        return const GeideaPaymentResult(approved: false, errorMessage: 'No response from terminal');
      }
      final map = Map<String, dynamic>.from(result);
      final approved = map['status'] == 'approved';
      final details = (map['details'] is Map)
          ? Map<String, dynamic>.from(map['details'] as Map)
          : <String, dynamic>{};
      return GeideaPaymentResult(
        approved: approved,
        approvalCode: details['approvalCode'] as String?,
        rrn: details['rrn'] as String?,
        details: details,
        errorMessage: approved ? null : (map['receipt'] as String? ?? 'Declined'),
      );
    } on TimeoutException {
      return const GeideaPaymentResult(approved: false, errorMessage: 'Terminal timed out');
    } on PlatformException catch (e) {
      return GeideaPaymentResult(approved: false, errorMessage: e.message ?? 'Terminal error');
    }
  }

  /// On-demand connection retry. Forces a fresh native connection attempt
  /// right now and, after [wait], reports whatever [checkCommunication]
  /// observes — i.e. whether the USBConnectionListener actually heard back
  /// `onUSBConnected` in that window. A synchronous "yes/no" isn't
  /// possible: the SDK's own callback is asynchronous, so this is a
  /// poll-after-delay, same tradeoff the terminal payment dialog itself
  /// makes.
  ///
  /// Two callers: Settings' "Detect Payment Terminals" test button
  /// ([source] "manual", the default), and [InvoiceScreen]'s terminal
  /// payment dialog itself ([source] "payment") — called unconditionally,
  /// every time, right before every payment attempt, never gated behind a
  /// prior [checkCommunication] check. That check only reads a cached
  /// flag (MainActivity's isUsbConnected, set by whichever
  /// USBConnectionListener callback last fired) — nothing keeps it live
  /// between that callback and the moment a payment actually starts, so a
  /// stale "yes" would otherwise let startPurchaseTransaction() run
  /// against a connection that's actually already dead, failing
  /// immediately inside the SDK before anything ever reaches the physical
  /// terminal. [source] only changes the native log/toast text, not the
  /// behavior.
  Future<bool> detectTerminal({
    Duration wait = const Duration(seconds: 4),
    String source = 'manual',
  }) async {
    if (_mock) {
      await Future.delayed(const Duration(seconds: 1));
      return true;
    }
    try {
      await _methodChannel.invokeMethod('detectTerminal', {'source': source});
    } on PlatformException {
      return false;
    }
    // Poll instead of blindly sleeping the full [wait] every time — a
    // healthy reconnect typically resolves in well under a second (seen as
    // low as ~40ms in the field), so a fixed sleep makes every payment
    // attempt pay the full delay even when the terminal was fine the whole
    // time. Still caps at [wait] total for a genuinely bad connection.
    final deadline = DateTime.now().add(wait);
    while (DateTime.now().isBefore(deadline)) {
      if (await checkCommunication()) return true;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return checkCommunication();
  }

  Future<void> cancelPayment() async {
    if (_mock) return;
    try {
      await _methodChannel.invokeMethod('cancelPayment');
    } on PlatformException {
      // Best-effort — nothing more useful to do if this fails.
    }
  }
}
