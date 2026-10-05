import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/device_config.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

// terminal_timeout_seconds: the server's value decides the terminal
// timeout when it is set; otherwise this device's Settings value counts.
void main() {
  Future<void> prefs(Map<String, Object> v) async {
    SharedPreferences.setMockInitialValues(v);
    await LocalPrefs.init();
  }

  test('parse: whole seconds, kept between 10 and 80, junk means no override', () {
    expect(DeviceConfig.parseTerminalTimeout('80'), 80);
    expect(DeviceConfig.parseTerminalTimeout(' 45 '), 45);
    expect(DeviceConfig.parseTerminalTimeout('5'), 10);
    expect(DeviceConfig.parseTerminalTimeout('120'), 80);
    expect(DeviceConfig.parseTerminalTimeout('0'), isNull);
    expect(DeviceConfig.parseTerminalTimeout('-3'), isNull);
    expect(DeviceConfig.parseTerminalTimeout('abc'), isNull);
    expect(DeviceConfig.parseTerminalTimeout(''), isNull);
    expect(DeviceConfig.parseTerminalTimeout(null), isNull);
  });

  test('no server value: the device\'s own setting counts (default 60)', () async {
    await prefs({});
    expect(LocalPrefs.terminalTimeoutSeconds, 60);
    await prefs({'waha.terminal_timeout_s': 40});
    expect(LocalPrefs.terminalTimeoutSeconds, 40);
  });

  test('the server value wins over the device setting', () async {
    await prefs({'waha.terminal_timeout_s': 40});
    await DeviceConfig.applyTerminalTimeout({'terminal_timeout_seconds': '80'});
    expect(LocalPrefs.remoteTerminalTimeoutSeconds, 80);
    expect(LocalPrefs.terminalTimeoutSeconds, 80);
    expect(LocalPrefs.localTerminalTimeoutSeconds, 40); // untouched, comes back if the property is removed
  });

  test('property removed from the server: back to the device setting', () async {
    await prefs({'waha.terminal_timeout_s': 40, 'waha.remote_terminal_timeout_s': 80});
    await DeviceConfig.applyTerminalTimeout({'default_language': 'en'});
    expect(LocalPrefs.remoteTerminalTimeoutSeconds, isNull);
    expect(LocalPrefs.terminalTimeoutSeconds, 40);
  });

  test('an unusable server value counts as no override', () async {
    await prefs({'waha.terminal_timeout_s': 40, 'waha.remote_terminal_timeout_s': 80});
    await DeviceConfig.applyTerminalTimeout({'terminal_timeout_seconds': 'soon'});
    expect(LocalPrefs.remoteTerminalTimeoutSeconds, isNull);
    expect(LocalPrefs.terminalTimeoutSeconds, 40);
  });

  test('a failed request (empty config) changes nothing', () async {
    await prefs({'waha.terminal_timeout_s': 40, 'waha.remote_terminal_timeout_s': 80});
    await DeviceConfig.applyTerminalTimeout({});
    expect(LocalPrefs.remoteTerminalTimeoutSeconds, 80);
    expect(LocalPrefs.terminalTimeoutSeconds, 80);
  });

  test('apply() applies all the organization properties together', () async {
    await prefs({});
    await DeviceConfig.apply({
      'enable_logging': 'true',
      'device_auto_restart_enabled': 'true',
      'device_auto_restart_hours': '3',
      'device_auto_restart_wait_minutes': '4',
      'terminal_timeout_seconds': '70',
    });
    expect(LocalPrefs.remoteLoggingEnabled, isTrue);
    expect(LocalPrefs.autoRestartEnabled, isTrue);
    expect(LocalPrefs.autoRestartPeriodHours, 3.0);
    expect(LocalPrefs.autoRestartWaitMinutes, 4);
    expect(LocalPrefs.terminalTimeoutSeconds, 70);
  });
}
