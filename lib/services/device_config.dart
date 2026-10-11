import 'auto_restart_service.dart';
import 'heartbeat_service.dart';
import 'local_prefs.dart';
import 'trace_log.dart';

/// The organization properties the kiosk reads from the server's public
/// config (`GET /api/config?orgId=`), applied in one place:
///  - `enable_logging`                       (see TraceLog.applyRemoteConfig)
///  - `device_auto_restart_enabled` / `_hours` / `_wait_minutes`
///                                           (see AutoRestartService.applyConfig)
///  - `terminal_timeout_seconds`      (below)
///  - `heartbeat_minutes`                    (see HeartbeatService.applyConfig)
///
/// An empty config means the request failed: nothing changes, so the last
/// known values stay in force.
class DeviceConfig {
  DeviceConfig._();

  // Same limits as the Settings field: the backend's terminal session lasts
  // 90 s, so an answer later than that could not be confirmed anyway.
  static const minTerminalTimeoutSeconds = 10;
  static const maxTerminalTimeoutSeconds = 80;

  /// `terminal_timeout_seconds`: whole seconds, kept between 10 and 80.
  /// Missing or unusable returns null = no override (the Settings value counts).
  static int? parseTerminalTimeout(String? raw) {
    final v = int.tryParse((raw ?? '').trim());
    if (v == null || v <= 0) return null;
    return v.clamp(minTerminalTimeoutSeconds, maxTerminalTimeoutSeconds);
  }

  static Future<void> applyTerminalTimeout(Map<String, String> config) async {
    if (config.isEmpty) return;
    final v = parseTerminalTimeout(config['terminal_timeout_seconds']);
    if (LocalPrefs.remoteTerminalTimeoutSeconds != v) {
      await LocalPrefs.setRemoteTerminalTimeoutSeconds(v);
    }
  }

  /// Applies every property from a config the server actually returned.
  static Future<void> apply(Map<String, String> config) async {
    await TraceLog.applyRemoteConfig(config);
    await AutoRestartService.applyConfig(config);
    await applyTerminalTimeout(config);
    await HeartbeatService.applyConfig(config);
  }
}
