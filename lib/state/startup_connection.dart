import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../router/app_router.dart';
import '../screens/server_connection_screen.dart';
import '../services/api_client.dart';
import 'auth_service.dart';
import 'browsing_mode_service.dart';

/// Seconds to wait after failed attempt number [attempt] (1-based): 10, 20, 40,
/// 80, 160 … doubling, held at [StartupConnection.maxWaitSeconds].
int retryDelaySeconds(int attempt) {
  var d = StartupConnection.firstWaitSeconds;
  for (var i = 1; i < attempt && d < StartupConnection.maxWaitSeconds; i++) {
    d *= 2;
  }
  return d.clamp(StartupConnection.firstWaitSeconds,
      StartupConnection.maxWaitSeconds);
}

/// Drives the connection popup shown when the active server can't be reached
/// at startup. Two states: [probing] (a request is in flight — "Connecting…")
/// and waiting (between attempts — "Connection failed" with a live countdown).
/// Retries on a doubling schedule until the server answers,
/// then finishes the startup sign-in that had to wait, and moves on.
///
/// Never switches server by itself — the only ways out are the server coming
/// back or the operator changing the connection (hidden gesture on the popup).
class StartupConnection extends ChangeNotifier {
  static const firstWaitSeconds = 10;
  static const maxWaitSeconds = 300;

  bool active = false;
  bool suspended = false; // Server Connection screen is open above the popup
  bool probing = false;
  int attempt = 0;
  int secondsLeft = 0;
  String? lastError;
  String? lastRaw; // raw exception text of the last failure, for Details

  /// Short, friendly version of [lastError]: "No answer within 5 seconds".
  String get shortError {
    final e = lastError;
    if (e == null || e.isEmpty) return "Can't reach the server";
    return e.split(' — ').first.split(' (').first;
  }

  /// Everything worth copying into a bug report.
  String get details => [
        'Server: ${AppConfig.apiBaseUrl}',
        'Failed attempts: $attempt',
        if (lastError != null) 'Problem: $lastError',
        if (lastRaw != null) 'Exception: $lastRaw',
      ].join('\n');

  // A refused connection fails in milliseconds; keep the loading state on
  // screen at least this long so a retry never looks like nothing happened.
  static const _minProbeShown = Duration(milliseconds: 900);

  Timer? _timer;
  ApiClient? _api;

  /// Called from main() when the first reachability probe failed.
  void begin(ApiClient api, String firstError) {
    _api = api;
    active = true;
    lastError = firstError;
    lastRaw = api.lastProbeRaw;
    attempt = 1; // the probe in main() was attempt 1 and failed
    probing = false;
    AppConfig.connection.removeListener(_onConnectionChanged);
    AppConfig.connection.addListener(_onConnectionChanged);
    _schedule();
    notifyListeners();
  }

  void _schedule() {
    secondsLeft = retryDelaySeconds(attempt);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (suspended || probing) return;
      secondsLeft--;
      if (secondsLeft <= 0) {
        unawaited(retryNow());
      } else {
        notifyListeners();
      }
    });
  }

  Future<void> retryNow() async {
    final api = _api;
    if (!active || probing || api == null) return;
    _timer?.cancel(); // cancels the backoff wait, if one is running
    _timer = null;
    probing = true;
    notifyListeners();
    final started = DateTime.now();
    final err = await api.probe();
    final shown = DateTime.now().difference(started);
    if (shown < _minProbeShown) {
      await Future<void>.delayed(_minProbeShown - shown);
    }
    probing = false;
    if (!active) return;
    if (err == null) {
      await _recovered(api);
    } else {
      attempt++;
      lastError = err;
      lastRaw = api.lastProbeRaw;
      _schedule();
      notifyListeners();
    }
  }

  /// Server answered: do the sign-in that startup skipped, then carry on.
  Future<void> _recovered(ApiClient api) async {
    _stop();
    notifyListeners(); // dismiss the popup the moment the server answers
    await authService.resolveStartupAuth(api, browsingModeService.mode);
    navigatorKey.currentState
        ?.pushNamedAndRemoveUntil(Routes.landing, (_) => false);
  }

  /// A successful switch from the connection screen already reached and signed
  /// in to the new server — nothing left for this popup to do.
  void _onConnectionChanged() {
    if (!active) return;
    _stop();
    notifyListeners();
  }

  void _stop() {
    active = false;
    _timer?.cancel();
    _timer = null;
    AppConfig.connection.removeListener(_onConnectionChanged);
  }

  /// Opens the connection screen above the popup; the popup steps aside while
  /// it is open and resumes (if still needed) when it closes.
  Future<void> openConnectionScreen({bool? customOn}) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    suspended = true;
    notifyListeners();
    await nav.push(MaterialPageRoute<void>(
        builder: (_) => ServerConnectionScreen(customOn: customOn)));
    suspended = false;
    if (active) {
      unawaited(retryNow()); // try straight away with whatever was saved
    }
    notifyListeners();
  }
}

final startupConnection = StartupConnection();
