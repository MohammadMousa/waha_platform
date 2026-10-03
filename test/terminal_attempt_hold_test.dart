import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/geidea_terminal_bridge.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

// The retry hold: a payment attempt handed to the terminal but never
// answered keeps a new attempt waiting for the terminal timeout.
void main() {
  Future<void> prefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    await LocalPrefs.init();
  }

  int now() => DateTime.now().millisecondsSinceEpoch;

  test('no pending attempt: no wait', () async {
    await prefs({});
    expect(GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
  });

  test('attempt started 10s ago with a 60s timeout: about 50s left', () async {
    await prefs({'waha.pending_terminal_attempt': '${now() - 10000}|abc'});
    final left = GeideaTerminalBridge.pendingAttemptRemaining();
    expect(left.inSeconds, inInclusiveRange(48, 50));
  });

  test('uses the configurable terminal timeout as the cap', () async {
    await prefs({
      'waha.terminal_timeout_s': 30,
      'waha.pending_terminal_attempt': '${now() - 10000}|abc',
    });
    expect(GeideaTerminalBridge.pendingAttemptRemaining().inSeconds, inInclusiveRange(18, 20));
  });

  test('attempt older than the timeout: no wait', () async {
    await prefs({'waha.pending_terminal_attempt': '${now() - 61000}|abc'});
    expect(GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
  });

  test('clock jumped backwards (e.g. after a reboot): never more than one timeout', () async {
    await prefs({'waha.pending_terminal_attempt': '${now() + 3600000}|abc'});
    expect(GeideaTerminalBridge.pendingAttemptRemaining().inSeconds, lessThanOrEqualTo(60));
  });

  test('a damaged record does not block payments', () async {
    await prefs({'waha.pending_terminal_attempt': 'garbage'});
    expect(GeideaTerminalBridge.pendingAttemptRemaining(), Duration.zero);
  });

  test('the record survives a restart (re-reading preferences)', () async {
    await prefs({'waha.pending_terminal_attempt': '${now() - 5000}|abc'});
    await LocalPrefs.init(); // what a fresh app start does
    expect(GeideaTerminalBridge.pendingAttemptRemaining().inSeconds, greaterThan(50));
  });
}
