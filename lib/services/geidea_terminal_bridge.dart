import 'dart:async';

import 'package:flutter/services.dart';

import 'local_prefs.dart';
import 'trace_log.dart';

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

  // The payment attempt currently waiting for the SDK, if any.
  _Attempt? _activeAttempt;
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

  /// Longest reference the Geidea SDK (pos-comm-sdk-ksa 1.3.0) can put on the
  /// wire. Its own check in TerminalResponder.initiatePurchaseTransaction is
  /// `^[a-zA-Z0-9]+$` and length <= 25, but the ECR field it builds is the tag
  /// `DF8110` — a hard-coded length byte of 0x10, i.e. exactly 16 bytes — so a
  /// 17-25 character reference passes the check yet yields a malformed frame.
  static const int ecrReferenceMaxLength = 16;

  /// Deterministic Geidea ECR reference for a Waha order id: the id with every
  /// non-alphanumeric character (the UUID hyphens) removed, cut to
  /// [ecrReferenceMaxLength] only because it must be. The order id itself is
  /// never changed. The backend's order ids are UUIDv7, so the kept prefix is
  /// the 48-bit millisecond timestamp + version nibble + 12 random bits — the
  /// part that differs between orders, and searchable as an id prefix.
  static String ecrReferenceFor(String orderId) {
    final alnum = orderId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return alnum.length <= ecrReferenceMaxLength
        ? alnum
        : alnum.substring(0, ecrReferenceMaxLength);
  }

  /// Time since the tablet booted, plus its boot counter — from the native
  /// side. Unlike the wall clock this never jumps when the time is corrected
  /// or changed. Null if the native call fails.
  static Future<({int elapsed, int boot})?> _monotonicNow() async {
    try {
      final m = await _methodChannel.invokeMethod<Map>('monotonicNow');
      final elapsed = (m?['elapsed'] as num?)?.toInt();
      if (elapsed == null) return null;
      return (elapsed: elapsed, boot: (m?['boot'] as num?)?.toInt() ?? -1);
    } catch (_) {
      return null;
    }
  }

  /// How much longer a new terminal payment must wait because an earlier
  /// attempt was handed to the terminal and has not had a final answer yet.
  /// Cancelling on screen cannot stop a payment the terminal already has, so
  /// a retry inside the terminal timeout could put a second purchase (same
  /// reference) on a terminal still busy with the first.
  ///
  /// The record holds the time-since-boot and boot counter of the moment the
  /// attempt was sent ("<elapsed>|<boot>|<ref>"). It never touches the wall
  /// clock, so a corrected or changed time cannot extend or shorten the wait.
  /// Same boot: the wait left is the terminal timeout minus the time since
  /// boot that has passed. A different boot (the tablet restarted), an
  /// unreadable or old-format record, or a failed native call all count as
  /// expired — the worst case is skipping the wait, never an endless one. The
  /// actual waiting is done by [waitOutHold] with a plain timer.
  static Future<Duration> pendingAttemptRemaining() async {
    final raw = LocalPrefs.pendingTerminalAttempt;
    if (raw == null) return Duration.zero;
    final parts = raw.split('|');
    if (parts.length < 3) return Duration.zero;
    final start = int.tryParse(parts[0]);
    final boot = int.tryParse(parts[1]);
    if (start == null || boot == null || start < 0) return Duration.zero;
    final now = await _monotonicNow();
    if (now == null || now.boot != boot) return Duration.zero;
    final capMs = LocalPrefs.terminalTimeoutSeconds * 1000;
    final elapsedMs = now.elapsed - start;
    if (elapsedMs < 0 || elapsedMs >= capMs) return Duration.zero;
    return Duration(milliseconds: capMs - elapsedMs);
  }

  /// True while an earlier attempt has no final answer recorded yet.
  static bool get hasPendingAttempt => LocalPrefs.pendingTerminalAttempt != null;

  /// Waits out [held] with a plain stopwatch — no wall clock, so it always
  /// ends after [held] at the latest. Calls [onTick] with the whole seconds
  /// left on every [tick]. Ends early, returning true, when [stillPending]
  /// turns false (the earlier attempt got its answer). Returns false at once
  /// if [shouldStop] says the screen is gone or the customer cancelled.
  static Future<bool> waitOutHold(
    Duration held, {
    required void Function(int secondsLeft) onTick,
    bool Function()? stillPending,
    bool Function()? shouldStop,
    Duration tick = const Duration(seconds: 1),
  }) async {
    final waited = Stopwatch()..start();
    while (true) {
      if (shouldStop != null && shouldStop()) return false;
      final left = held - waited.elapsed;
      if (left <= Duration.zero) return true;
      if (stillPending != null && !stillPending()) return true;
      onTick((left.inMilliseconds / 1000).ceil());
      await Future<void>.delayed(tick);
    }
  }

  /// Clears the pending-attempt record only if it is still THIS attempt's: a
  /// late answer to an old, cancelled attempt must not lift the wait that a
  /// newer attempt has since set.
  static Future<void> _clearPendingAttempt(String marker) async {
    if (LocalPrefs.pendingTerminalAttempt == marker) {
      await LocalPrefs.setPendingTerminalAttempt(null);
    } else {
      TraceLog.log('Terminal: late answer for an older attempt ($marker) — newer attempt still pending, record kept');
    }
  }

  /// [amount] in major currency units (e.g. SAR), matching `order.total`
  /// directly — no minor-unit conversion. [reference] is the Waha order id
  /// (already globally unique). The SDK rejects a raw UUID locally with error
  /// 16, so it is sent as [ecrReferenceFor]`(reference)` instead.
  Future<GeideaPaymentResult> startPayment({
    required double amount,
    required String reference,
    Duration? timeout,
  }) async {
    final ecrReference = ecrReferenceFor(reference);
    TraceLog.log('Terminal: Geidea reference — orderId=$reference '
        'sent=$ecrReference length=${ecrReference.length}');
    if (_mock) {
      await Future.delayed(const Duration(seconds: 2));
      return GeideaPaymentResult(
        approved: true,
        approvalCode: '000000',
        rrn: '000000000000',
        details: {'mock': true, 'reference': reference, 'amount': amount},
      );
    }
    final clock = Stopwatch()..start();
    TraceLog.log('Terminal: → SDK startPayment amount=$amount timeout=${timeout?.inSeconds ?? 'none'}s');
    // Marked before the command goes out; cleared only when the SDK gives a
    // final answer (below). A timeout leaves it in place — it lapses on its
    // own once the terminal timeout has passed.
    final mono = await _monotonicNow();
    final marker = '${mono?.elapsed ?? -1}|${mono?.boot ?? -1}|$ecrReference';
    await LocalPrefs.setPendingTerminalAttempt(marker);

    // The wait for the SDK's answer is OWNED by this attempt: its timer and
    // its result live in [attempt], and cancelPayment() ends both. Before,
    // the timer of a payment the customer had cancelled was never stopped, so
    // it fired a minute later — in the middle of the NEXT payment — and
    // stopped that payment's watch, flagged it as given up and triggered a
    // false "no callback" log upload.
    final attempt = _Attempt();
    _activeAttempt = attempt;

    if (timeout != null) {
      attempt.timer = Timer(timeout, () {
        if (attempt.result.isCompleted) return;
        TraceLog.log('Terminal: NO reply from the SDK after ${clock.elapsedMilliseconds}ms (Dart-side timeout) — dumping SDK state');
        unawaited(sdkDump('payment:timeout'));
        attempt.result.complete(const GeideaPaymentResult(approved: false, errorMessage: 'Terminal timed out'));
      });
    }

    _methodChannel.invokeMethod<Map>('startPayment', {
      'amount': amount,
      'reference': ecrReference,
      'isPrinterEnabled': false, // kiosk has no printer
    }).then((result) async {
      attempt.timer?.cancel();
      // Any answer from the native side (approved, declined, or an SDK error
      // result) means the terminal is no longer busy with this attempt — also
      // an answer that arrives after the cashier cancelled or the timeout
      // passed.
      await _clearPendingAttempt(marker);
      final late = attempt.result.isCompleted;
      final parsed = _parseResult(result, clock, late: late);
      if (late) {
        TraceLog.log('Terminal: LATE answer for an attempt already given up on '
            '(cancelled or timed out): approved=${parsed.approved} — ${parsed.approved ? "the customer may have been charged; reconcile this order" : "nothing to do"}');
        return;
      }
      attempt.result.complete(parsed);
    }, onError: (Object e) async {
      attempt.timer?.cancel();
      await _clearPendingAttempt(marker);
      if (attempt.result.isCompleted) return;
      if (e is PlatformException) {
        TraceLog.log('Terminal: SDK call failed after ${clock.elapsedMilliseconds}ms: ${e.code} ${e.message}');
        unawaited(sdkDump('payment:exception'));
        attempt.result.complete(GeideaPaymentResult(approved: false, errorMessage: e.message ?? 'Terminal error'));
      } else {
        attempt.result.completeError(e);
      }
    });

    try {
      return await attempt.result.future;
    } finally {
      if (identical(_activeAttempt, attempt)) _activeAttempt = null;
    }
  }

  GeideaPaymentResult _parseResult(Map? result, Stopwatch clock, {required bool late}) {
    if (result == null) {
      TraceLog.log('Terminal: ← SDK returned null after ${clock.elapsedMilliseconds}ms');
      return const GeideaPaymentResult(approved: false, errorMessage: 'No response from terminal');
    }
    final map = Map<String, dynamic>.from(result);
    final approved = map['status'] == 'approved';
    TraceLog.log('Terminal: ← SDK replied after ${clock.elapsedMilliseconds}ms '
        'status=${map['status']} receipt=${_clip(map['receipt'] as String? ?? '', 120)}');
    // A late decline must not run the SDK dump: it would stop the watch of a
    // newer payment that is in flight by now.
    if (!approved && !late) unawaited(sdkDump('payment:not-approved'));
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
  }

  static String _clip(String s, int max) {
    final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > max ? flat.substring(0, max) : flat;
  }

  /// Real terminal handshake over USB (the SDK's `startCheckStatus`): sends the
  /// SDK's own check-connection frame and waits for the terminal's reply.
  /// Unlike [checkCommunication] — which only reports a local flag — this
  /// proves the terminal answers. Result keys: status (ok | error | timeout |
  /// busy | not_initialized | exception), message, json, raw, elapsedMs.
  Future<Map<String, dynamic>> checkStatus({Duration timeout = const Duration(seconds: 6)}) async {
    if (_mock) return {'status': 'ok', 'message': 'mock terminal', 'elapsedMs': 0};
    try {
      final r = await _methodChannel.invokeMethod<Map>('checkStatus', {'timeoutMs': timeout.inMilliseconds});
      final map = Map<String, dynamic>.from(r ?? const {});
      TraceLog.log('Terminal: handshake (startCheckStatus) → $map');
      return map;
    } on PlatformException catch (e) {
      TraceLog.log('Terminal: handshake failed: ${e.code} ${e.message}');
      return {'status': 'exception', 'message': e.message ?? e.code};
    }
  }

  /// What the SDK believes right now, its own log file and captured log lines,
  /// and the USB inventory — one text block for the Settings screen.
  Future<String> sdkState() async {
    if (_mock) return 'mock terminal — no SDK';
    try {
      return await _methodChannel.invokeMethod<String>('sdkState') ?? '';
    } on PlatformException catch (e) {
      return 'SDK state failed: ${e.message}';
    }
  }

  /// Sends the same report to the trace log (native side).
  Future<void> sdkDump(String reason) async {
    if (_mock) return;
    try {
      await _methodChannel.invokeMethod<bool>('sdkDump', {'reason': reason});
    } on PlatformException {
      // diagnostics only
    }
  }

  /// Android's recorded reasons why earlier processes of this app ended
  /// (crash, low memory, force-stop ...). Needs Android 11+; older versions get
  /// a plain "not available" line. Never throws.
  Future<String> exitReasons() async {
    try {
      return await _methodChannel.invokeMethod<String>('exitReasons') ?? '';
    } catch (e) {
      return 'Exit reasons could not be read: $e';
    }
  }

  /// Tells native code the server URL, so the log viewer (which runs without
  /// Flutter) can upload logs. Diagnostics only.
  Future<void> setApiBaseUrl(String url) async {
    try {
      await _methodChannel.invokeMethod<bool>('setApiBaseUrl', {'url': url});
    } catch (_) {
      // diagnostics only
    }
  }

  /// Tells the native side (AutoLogUploader) which organization this kiosk
  /// is logged in as, so it can read that org's auto-log-upload properties.
  /// Native has no other way to know this — it isn't persisted to
  /// SharedPreferences the way the auth token / server URL are. Pass null
  /// on logout.
  Future<void> setOrgId(int? orgId) async {
    try {
      await _methodChannel.invokeMethod('setOrgId', {'orgId': orgId});
    } catch (_) {
      // diagnostics only
    }
  }

  /// Uploads the trace log (last ~1 MB) plus SDK logs and the USB inventory
  /// to the Waha backend as `logs_<timestamp>.txt`. Result keys: ok, id, url,
  /// fileName, bytes, baseUrl, message.
  Future<Map<String, dynamic>> uploadLog() async {
    try {
      final r = await _methodChannel.invokeMethod<Map>('uploadLog');
      return Map<String, dynamic>.from(r ?? const {});
    } catch (e) {
      return {'ok': false, 'message': '$e'};
    }
  }

  /// Human-readable summary of an [uploadLog] result — shared by Settings'
  /// "Upload log" button and ScannerManager's `cmd-upload-logs` QR command,
  /// so both show the customer/support person the exact same text.
  static String describeUploadLogResult(Map<String, dynamic> r) {
    if (r['ok'] == true) {
      return 'Uploaded.\n\n'
          'LOG ID: ${r['id']}\n'
          '${r['url']}\n\n'
          '${r['fileName']} (${r['bytes']} bytes)\n\n'
          'Send the LOG ID to the developer.';
    }
    return 'Upload FAILED.\n\n${r['message'] ?? 'unknown error'}\n\nServer: ${r['baseUrl'] ?? 'unknown'}';
  }

  Future<bool> clearLog() async {
    try {
      return await _methodChannel.invokeMethod<bool>('clearLog') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openLogViewer() async {
    try {
      await _methodChannel.invokeMethod<bool>('openLogViewer');
    } catch (_) {
      // diagnostics only
    }
  }

  /// One complete diagnostic: USB environment, SDK state, forced reconnect
  /// (does the port really open?), the real startCheckStatus request with a
  /// millisecond timeline, a raw probe of every serial channel, the SDK status
  /// request again, the six-signal ladder and a verdict (A-D). Takes ~30 s.
  /// The whole report is also written to the trace log.
  Future<String> fullDiagnostic() async {
    if (_mock) return 'mock terminal — nothing to diagnose';
    try {
      return await _methodChannel.invokeMethod<String>('fullDiagnostic') ?? '';
    } on PlatformException catch (e) {
      return 'Full diagnostic failed: ${e.message}';
    }
  }

  /// Opens every CDC data channel of the terminal one at a time, sends the
  /// SDK's check frame on each and reports which (if any) answers. Briefly
  /// disconnects the SDK; never call during a payment.
  Future<String> probeChannels() async {
    if (_mock) return 'mock terminal — nothing to probe';
    try {
      return await _methodChannel.invokeMethod<String>('probeChannels') ?? '';
    } on PlatformException catch (e) {
      return 'Probe failed: ${e.message}';
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

  /// Clean start for a payment: closes whatever USB connection the SDK still
  /// holds, opens a fresh one, and returns true only when the serial port
  /// really opened (not merely when the SDK says "connected"). False means
  /// the terminal is not ready — don't start the payment.
  Future<bool> prepareTerminal({String reason = 'payment'}) async {
    if (_mock) {
      await Future.delayed(const Duration(seconds: 1));
      return true;
    }
    try {
      final ok = await _methodChannel
          .invokeMethod<bool>('prepareTerminal', {'reason': reason})
          .timeout(const Duration(seconds: 25));
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Before a payment: makes sure the SDK's USB service is bound, re-opening
  /// it if the SDK destroyed it (it does so about a minute after the app was
  /// stopped, and nothing re-binds it — every payment then gets no answer).
  /// `ready` is true when the terminal is ready. A healthy service returns at
  /// once. If the native call itself fails this reports ready, so a fault in
  /// the check can never stop a sale by itself.
  ///
  /// `reopened` is true when the service had been lost: an earlier attempt's
  /// command then went to a dead service and never reached the terminal, so
  /// there is nothing left to wait for.
  Future<({bool ready, bool reopened})> ensureTerminalService() async {
    if (_mock) return (ready: true, reopened: false);
    try {
      final m = await _methodChannel
          .invokeMethod<Map>('ensureTerminalService')
          .timeout(const Duration(seconds: 20));
      if (m == null) return (ready: true, reopened: false);
      return (ready: m['ready'] != false, reopened: m['reopened'] == true);
    } catch (_) {
      return (ready: true, reopened: false);
    }
  }

  Future<void> cancelPayment() async {
    if (_mock) return;
    // End the wait for this attempt now, so its timer cannot fire later.
    final attempt = _activeAttempt;
    if (attempt != null) {
      attempt.timer?.cancel();
      if (!attempt.result.isCompleted) {
        attempt.result.complete(const GeideaPaymentResult(approved: false, errorMessage: 'Cancelled'));
      }
    }
    try {
      await _methodChannel.invokeMethod('cancelPayment');
    } on PlatformException {
      // Best-effort — nothing more useful to do if this fails.
    }
  }
}

/// One payment attempt's wait for the SDK's answer: the result the caller
/// awaits and the timeout timer. Both belong to the attempt, so ending the
/// attempt (an answer, a cancel) ends its timer too.
class _Attempt {
  final Completer<GeideaPaymentResult> result = Completer<GeideaPaymentResult>();
  Timer? timer;
}
