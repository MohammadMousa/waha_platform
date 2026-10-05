import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/geidea_terminal_bridge.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

// When the terminal answers "Terminal busy", new payments are refused for a
// short cool-down; any other outcome starts none.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.waha/geidea');
  Map<String, Object?> answer = {};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    GeideaTerminalBridge.busyCooldown = const Duration(milliseconds: 300);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'monotonicNow') return {'elapsed': 100000, 'boot': 7};
      if (c.method == 'startPayment') return answer;
      return true;
    });
  });

  tearDown(() {
    GeideaTerminalBridge.busyCooldown = const Duration(seconds: 10);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<GeideaPaymentResult> pay() => GeideaTerminalBridge.instance
      .startPayment(amount: 1.5, reference: '01a0f718-0f7f-75c8-ace5-ab743730be6d', timeout: const Duration(seconds: 5));

  test('recognises the busy message', () {
    expect(GeideaTerminalBridge.isBusyMessage('Terminal busy, please try again'), isTrue);
    expect(GeideaTerminalBridge.isBusyMessage('TERMINAL BUSY'), isTrue);
    expect(GeideaTerminalBridge.isBusyMessage('Declined'), isFalse);
    expect(GeideaTerminalBridge.isBusyMessage(null), isFalse);
  });

  test('a busy answer starts the cool-down, and it ends on its own', () async {
    answer = {'status': 'declined', 'receipt': 'Terminal busy, please try again', 'details': {}};
    expect((await pay()).approved, isFalse);
    final left = GeideaTerminalBridge.busyCooldownRemaining();
    expect(left, greaterThan(Duration.zero));
    expect(left, lessThanOrEqualTo(const Duration(milliseconds: 300)));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(GeideaTerminalBridge.busyCooldownRemaining(), Duration.zero);
  });

  test('an ordinary decline starts no cool-down', () async {
    // wait out any cool-down left by the previous test
    await Future<void>.delayed(const Duration(milliseconds: 350));
    answer = {'status': 'declined', 'receipt': 'DECLINED (host code 116)', 'details': {}};
    await pay();
    expect(GeideaTerminalBridge.busyCooldownRemaining(), Duration.zero);
  });

  test('an approval starts no cool-down', () async {
    answer = {'status': 'approved', 'receipt': 'ok', 'details': {}};
    expect((await pay()).approved, isTrue);
    expect(GeideaTerminalBridge.busyCooldownRemaining(), Duration.zero);
  });
}
