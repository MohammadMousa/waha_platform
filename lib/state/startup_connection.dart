import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../router/app_router.dart';
import '../screens/server_connection_screen.dart';
import '../services/api_client.dart';
import 'auth_service.dart';
import 'browsing_mode_service.dart';

/// Seconds to wait before retry number [attempt] (1-based): 10, 20, 30 … up to
/// [StartupConnection.maxWaitSeconds].
int retryDelaySeconds(int attempt) => (StartupConnection.stepSeconds * attempt)
    .clamp(StartupConnection.stepSeconds, StartupConnection.maxWaitSeconds);

/// Drives the "Connecting…" popup shown when the active server can't be
/// reached at startup. Retries on a growing schedule until the server answers,
/// then finishes the startup sign-in that had to wait, and moves on.
///
/// Never switches server by itself — the only ways out are the server coming
/// back or the operator changing the connection (hidden gesture on the popup).
class StartupConnection extends ChangeNotifier {
  static const stepSeconds = 10;
  static const maxWaitSeconds = 60;

  bool active = false;
  bool suspended = false; // Server Connection screen is open above the popup
  bool probing = false;
  int attempt = 0;
  int secondsLeft = 0;
  String? lastError;

  Timer? _timer;
  ApiClient? _api;

  /// Called from main() when the first reachability probe failed.
  void begin(ApiClient api, String firstError) {
    _api = api;
    active = true;
    lastError = firstError;
    attempt = 1;
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
    probing = true;
    notifyListeners();
    final err = await api.probe();
    probing = false;
    if (!active) return;
    if (err == null) {
      await _recovered(api);
    } else {
      attempt++;
      lastError = err;
      _schedule();
      notifyListeners();
    }
  }

  /// Server answered: do the sign-in that startup skipped, then carry on.
  Future<void> _recovered(ApiClient api) async {
    _stop();
    await authService.resolveStartupAuth(api, browsingModeService.mode);
    notifyListeners();
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
