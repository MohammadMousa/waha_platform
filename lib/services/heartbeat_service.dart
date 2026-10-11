import 'dart:async';

import '../state/auth_service.dart';
import 'api_client.dart';
import 'local_prefs.dart';
import 'trace_log.dart';

/// Tells the server the kiosk is alive while it is otherwise idle (POST
/// /api/kiosk/heartbeat), every `heartbeat_minutes` (organization property;
/// 0 or missing = off). The server also counts any other signed-in call as a
/// sign of life, so this only fills the quiet gaps.
class HeartbeatService {
  HeartbeatService._();
  static final HeartbeatService instance = HeartbeatService._();

  static const maxMinutes = 1440;

  ApiClient? _api;
  Timer? _timer;
  int _minutes = 0;

  /// `heartbeat_minutes`: whole minutes, 0 (off) to 1440. Missing or
  /// unusable means off.
  static int parseMinutes(String? raw) {
    final v = int.tryParse((raw ?? '').trim());
    if (v == null || v <= 0) return 0;
    return v > maxMinutes ? maxMinutes : v;
  }

  /// Applies the property from a config the server actually returned. An
  /// empty map means the request failed and changes nothing.
  static Future<void> applyConfig(Map<String, String> config) async {
    if (config.isEmpty) return;
    final m = parseMinutes(config['heartbeat_minutes']);
    if (LocalPrefs.heartbeatMinutes != m) await LocalPrefs.setHeartbeatMinutes(m);
    instance._schedule(m);
  }

  /// Starts with the last value the server gave, before the next config
  /// arrives.
  void start(ApiClient api) {
    _api = api;
    _schedule(LocalPrefs.heartbeatMinutes);
  }

  void _schedule(int minutes) {
    if (_api == null || minutes == _minutes) return;
    _minutes = minutes;
    _timer?.cancel();
    _timer = null;
    if (minutes <= 0) return;
    TraceLog.log('HEARTBEAT: every $minutes min');
    _timer = Timer.periodic(Duration(minutes: minutes), (_) => unawaited(_beat()));
  }

  Future<void> _beat() async {
    final api = _api;
    final token = authService.token;
    if (api == null || token == null || !authService.isDeviceSession) return;
    try {
      await api.kioskHeartbeat(token);
    } catch (e) {
      TraceLog.log('HEARTBEAT: not sent ($e)');
    }
  }
}
