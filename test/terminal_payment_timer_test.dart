import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/geidea_terminal_bridge.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

// The wait for the terminal's answer belongs to its attempt: Cancel stops the
// timer, a timeout is not carried into the next payment, and a late answer
// to an old attempt is only logged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.waha/geidea');
  final calls = <String>[];
  Completer<Map<String, Object?>>? sdkAnswer;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    calls.clear();
    sdkAnswer = Completer<Map<String, Object?>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'monotonicNow') return {'elapsed': 100000, 'boot': 7};
      if (call.method == 'startPayment') return sdkAnswer!.future;
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  final bridge = GeideaTerminalBridge.instance;
  Future<GeideaPaymentResult> pay(Duration timeout) =>
      bridge.startPayment(amount: 1.5, reference: '01a0f718-0f7f-75c8-ace5-ab743730be6d', timeout: timeout);

  test('an approved answer returns approved and clears the pending record', () async {
    final f = pay(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(LocalPrefs.pendingTerminalAttempt, isNotNull);
    sdkAnswer!.complete({'status': 'approved', 'receipt': '', 'details': {'approvalCode': '1'}});
    final r = await f;
    expect(r.approved, isTrue);
    expect(LocalPrefs.pendingTerminalAttempt, isNull);
  });

  test('no answer: the timeout fires once and reports a timeout', () async {
    final r = await pay(const Duration(milliseconds: 150));
    expect(r.approved, isFalse);
    expect(r.errorMessage, 'Terminal timed out');
    expect(calls.where((c) => c == 'sdkDump').length, 1);
    expect(LocalPrefs.pendingTerminalAttempt, isNotNull); // lapses on its own
  });

  test('cancel stops the timer: no timeout dump fires afterwards', () async {
    final f = pay(const Duration(milliseconds: 300));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await bridge.cancelPayment();
    final r = await f;
    expect(r.errorMessage, 'Cancelled');
    await Future<void>.delayed(const Duration(milliseconds: 500)); // well past the old timer
    expect(calls.where((c) => c == 'sdkDump'), isEmpty);
  });

  test("a cancelled attempt's timer cannot hit the next payment", () async {
    final first = pay(const Duration(milliseconds: 300));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await bridge.cancelPayment();
    await first;
    // next payment starts while the old timer's time has not passed yet
    sdkAnswer = Completer<Map<String, Object?>>();
    final second = pay(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(calls.where((c) => c == 'sdkDump'), isEmpty);
    sdkAnswer!.complete({'status': 'approved', 'receipt': '', 'details': {}});
    expect((await second).approved, isTrue);
  });

  test('a late answer after cancel is ignored by the caller and clears the record', () async {
    final first = sdkAnswer!;
    final f = pay(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await bridge.cancelPayment();
    expect((await f).errorMessage, 'Cancelled');
    expect(LocalPrefs.pendingTerminalAttempt, isNotNull);
    first.complete({'status': 'approved', 'receipt': '', 'details': {}});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(LocalPrefs.pendingTerminalAttempt, isNull);
    expect(calls.where((c) => c == 'sdkDump'), isEmpty);
  });

  test('a late decline after cancel does not run the SDK dump', () async {
    final first = sdkAnswer!;
    final f = pay(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await bridge.cancelPayment();
    await f;
    first.complete({'status': 'declined', 'receipt': 'declined', 'details': {}});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls.where((c) => c == 'sdkDump'), isEmpty);
  });
}
