import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/geidea_terminal_bridge.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

// The retry hold: a payment attempt handed to the terminal but never
// answered keeps a new attempt waiting for the terminal timeout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.waha/geidea');
  // What the (fake) native side reports as "now": time since boot + boot count.
  var nowElapsed = 100000;
  var nowBoot = 7;
  bool nativeFails = false;

  Future<void> prefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    await LocalPrefs.init();
  }

  setUp(() {
    nowElapsed = 100000;
    nowBoot = 7;
    nativeFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'monotonicNow') {
        if (nativeFails) throw PlatformException(code: 'x');
        return {'elapsed': nowElapsed, 'boot': nowBoot};
      }
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('no pending attempt: no wait', () async {
    await prefs({});
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
  });

  test('same boot, attempt started 10s ago with a 60s timeout: 50s left', () async {
    await prefs({'waha.pending_terminal_attempt': '90000|7|abc'});
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), const Duration(seconds: 50));
  });

  test('uses the configurable terminal timeout as the cap', () async {
    await prefs({'waha.terminal_timeout_s': 30, 'waha.pending_terminal_attempt': '90000|7|abc'});
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), const Duration(seconds: 20));
  });

  test('attempt older than the timeout: no wait', () async {
    await prefs({'waha.pending_terminal_attempt': '39000|7|abc'});
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
  });

  test('the tablet restarted (different boot): expired', () async {
    await prefs({'waha.pending_terminal_attempt': '90000|6|abc'});
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
  });

  test('boot count unknown on both sides but time since boot went back (restart): expired', () async {
    nowBoot = -1;
    nowElapsed = 5000;
    await prefs({'waha.pending_terminal_attempt': '90000|-1|abc'});
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
  });

  test('the wall clock plays no part: nothing in the record or the result depends on it', () async {
    // The record carries no wall-clock time at all, and the answer depends
    // only on the native time since boot — so a corrected or changed tablet
    // time cannot change it. Same input, same answer, however often asked.
    await prefs({'waha.pending_terminal_attempt': '90000|7|abc'});
    final first = await GeideaTerminalBridge.pendingAttemptRemaining();
    final second = await GeideaTerminalBridge.pendingAttemptRemaining();
    expect(first, second);
  });

  test('an old-format or damaged record does not block payments', () async {
    await prefs({'waha.pending_terminal_attempt': '1790000000000|abc'}); // old wall-clock format
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
    await prefs({'waha.pending_terminal_attempt': 'garbage'});
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
  });

  test('the native call failing never blocks payments', () async {
    nativeFails = true;
    await prefs({'waha.pending_terminal_attempt': '90000|7|abc'});
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
  });

  test('the record survives an app restart within the same boot (re-reading preferences)', () async {
    await prefs({'waha.pending_terminal_attempt': '95000|7|abc'});
    await LocalPrefs.init(); // what a fresh app start does
    expect(await GeideaTerminalBridge.pendingAttemptRemaining(), const Duration(seconds: 55));
  });

  group('waitOutHold (plain timer)', () {
    test('ends after the hold even if the earlier attempt never gets an answer', () async {
      final sw = Stopwatch()..start();
      final ticks = <int>[];
      final ok = await GeideaTerminalBridge.waitOutHold(
        const Duration(milliseconds: 200),
        onTick: ticks.add,
        stillPending: () => true,
        tick: const Duration(milliseconds: 20),
      );
      expect(ok, isTrue);
      expect(sw.elapsedMilliseconds, inInclusiveRange(190, 600));
      expect(ticks, isNotEmpty);
    });

    test('ends early when the earlier attempt gets its answer', () async {
      var pending = true;
      Future<void>.delayed(const Duration(milliseconds: 60), () => pending = false);
      final sw = Stopwatch()..start();
      final ok = await GeideaTerminalBridge.waitOutHold(
        const Duration(seconds: 30),
        onTick: (_) {},
        stillPending: () => pending,
        tick: const Duration(milliseconds: 20),
      );
      expect(ok, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('stops at once when the customer cancels', () async {
      var cancelled = false;
      Future<void>.delayed(const Duration(milliseconds: 60), () => cancelled = true);
      final ok = await GeideaTerminalBridge.waitOutHold(
        const Duration(seconds: 30),
        onTick: (_) {},
        shouldStop: () => cancelled,
        tick: const Duration(milliseconds: 20),
      );
      expect(ok, isFalse);
    });

    test('counts down in whole seconds and never waits longer than the hold', () async {
      final ticks = <int>[];
      await GeideaTerminalBridge.waitOutHold(
        const Duration(milliseconds: 2500),
        onTick: ticks.add,
        tick: const Duration(milliseconds: 500),
      );
      expect(ticks.first, 3);
      expect(ticks.last, 1);
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i], lessThanOrEqualTo(ticks[i - 1]));
      }
    });
  });
}
