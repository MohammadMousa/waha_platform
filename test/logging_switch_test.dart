import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/services/trace_log.dart';

// Logging is on when the local Settings switch OR the dashboard property
// `enable_logging` is on. Both off = off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.waha/geidea');
  final pushed = <bool>[];

  Future<void> start(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await LocalPrefs.init();
    pushed.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setLoggingEnabled') pushed.add((call.arguments as Map)['enabled'] as bool);
      return true;
    });
  }

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('both off: logging is off', () async {
    await start({});
    expect(LocalPrefs.effectiveLoggingEnabled, isFalse);
  });

  test('local switch alone turns it on', () async {
    await start({'waha.logging_enabled': true});
    expect(LocalPrefs.effectiveLoggingEnabled, isTrue);
  });

  test('dashboard property alone turns it on and is pushed to the native side', () async {
    await start({});
    await TraceLog.applyRemoteConfig({'enable_logging': 'true', 'other': 'x'});
    expect(LocalPrefs.remoteLoggingEnabled, isTrue);
    expect(LocalPrefs.effectiveLoggingEnabled, isTrue);
    expect(pushed.last, isTrue);
  });

  test('dashboard switched off while the local switch is off: logging goes off', () async {
    await start({'waha.remote_logging_enabled': true});
    await TraceLog.applyRemoteConfig({'enable_logging': 'false'});
    expect(LocalPrefs.effectiveLoggingEnabled, isFalse);
    expect(pushed.last, isFalse);
  });

  test('dashboard off but local on: stays on', () async {
    await start({'waha.logging_enabled': true, 'waha.remote_logging_enabled': true});
    await TraceLog.applyRemoteConfig({'enable_logging': 'false'});
    expect(LocalPrefs.effectiveLoggingEnabled, isTrue);
  });

  test('a missing property counts as off', () async {
    await start({'waha.remote_logging_enabled': true});
    await TraceLog.applyRemoteConfig({'default_language': 'en'});
    expect(LocalPrefs.remoteLoggingEnabled, isFalse);
  });

  test('a failed request (empty config) changes nothing', () async {
    await start({'waha.remote_logging_enabled': true});
    await TraceLog.applyRemoteConfig({});
    expect(LocalPrefs.remoteLoggingEnabled, isTrue);
    expect(pushed, isEmpty);
  });
}
