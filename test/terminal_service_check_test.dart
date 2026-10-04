import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/services/geidea_terminal_bridge.dart';

// Before a payment the app asks the native side to make sure the SDK's USB
// service is bound. A fault in that check must never stop a sale by itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.waha/geidea');

  void native(Future<Object?> Function(MethodCall) handler) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('service healthy: ready, not reopened', () async {
    native((c) async => c.method == 'ensureTerminalService' ? {'ready': true, 'reopened': false} : null);
    final r = await GeideaTerminalBridge.instance.ensureTerminalService();
    expect(r.ready, isTrue);
    expect(r.reopened, isFalse);
  });

  test('service was lost and came back: ready and reopened (so an old pending attempt is moot)', () async {
    native((c) async => c.method == 'ensureTerminalService' ? {'ready': true, 'reopened': true} : null);
    final r = await GeideaTerminalBridge.instance.ensureTerminalService();
    expect(r.ready, isTrue);
    expect(r.reopened, isTrue);
  });

  test('service could not be re-opened: not ready, so the payment is not started', () async {
    native((c) async => c.method == 'ensureTerminalService' ? {'ready': false, 'reopened': true} : null);
    final r = await GeideaTerminalBridge.instance.ensureTerminalService();
    expect(r.ready, isFalse);
  });

  test('the native call failing never blocks a sale', () async {
    native((c) async => throw PlatformException(code: 'boom'));
    final r = await GeideaTerminalBridge.instance.ensureTerminalService();
    expect(r.ready, isTrue);
    expect(r.reopened, isFalse);
  });

  test('no answer from native: treated as ready', () async {
    native((c) async => null);
    expect((await GeideaTerminalBridge.instance.ensureTerminalService()).ready, isTrue);
  });
}
