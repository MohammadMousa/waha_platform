import 'dart:async';

import '../config/app_config.dart';
import '../config/connection_settings.dart';
import '../models/auth_session.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
import 'api_client.dart';
import 'api_exceptions.dart';
import 'local_prefs.dart';

/// What the operator typed to sign in to the new server. Used once, never
/// stored: Kiosk = device username + PIN, Normal = username + password,
/// Shopping = nothing (a guest account is created).
class SwitchCredentials {
  final String username;
  final String secret;
  const SwitchCredentials(this.username, this.secret);
}

class SwitchResult {
  final bool ok;

  /// Which step failed, for the message: 'address' | 'server' | 'login'.
  final String? failedStep;
  final String message;
  const SwitchResult.success(this.message)
      : ok = true,
        failedStep = null;
  const SwitchResult.failure(this.failedStep, this.message) : ok = false;
}

/// Moves the app to a different server without ever breaking the one that
/// works: the candidate is tested and signed in to with a separate client, and
/// only if both succeed is anything on the app changed. Any failure returns
/// early and leaves the current connection, session and cart untouched.
class ConnectionSwitcher {
  ConnectionSwitcher._();

  /// [customEnabled] = the switch position being applied. With it true,
  /// [custom] becomes the active server; with it false the app returns to
  /// the project default (and the saved custom fields are kept as they are).
  static Future<SwitchResult> apply({
    required bool customEnabled,
    required CustomConnection custom,
    required ApiClient activeApi,
    required OrderFlowController order,
    SwitchCredentials? credentials,
  }) async {
    // Where we are going.
    String targetUrl;
    if (customEnabled) {
      final err = custom.validate();
      if (err != null) return SwitchResult.failure('address', err);
      targetUrl = custom.url;
    } else {
      targetUrl = AppConfig.defaultApiBaseUrl;
    }

    // Same server as now — nothing to sign in to again, just record the choice.
    if (targetUrl == AppConfig.apiBaseUrl) {
      await _record(customEnabled, custom);
      return const SwitchResult.success('Already using this server');
    }

    final mode = browsingModeService.mode;
    // The username is optional: left blank, the one already signed in on this
    // device is reused, so the operator only types the PIN/password.
    final typedUser = credentials?.username.trim() ?? '';
    final username =
        typedUser.isNotEmpty ? typedUser : (authService.username ?? '');
    final secret = credentials?.secret ?? '';
    if (mode != BrowsingMode.shopping && (username.isEmpty || secret.isEmpty)) {
      final what = mode == BrowsingMode.kiosk ? 'PIN' : 'password';
      return SwitchResult.failure(
          'login',
          username.isEmpty
              ? 'Enter the username and $what for the new server'
              : 'Enter the $what for the new server');
    }
    final signInAs = SwitchCredentials(username, secret);

    // 1) Is there a Waha server there? Separate client, no token.
    final probeClient = ApiClient(baseUrl: targetUrl);
    final reachError = await probeClient.probe();
    if (reachError != null) return SwitchResult.failure('server', reachError);

    // 2) Can we sign in? Same separate client; one attempt, no retry loop
    //    of our own (a wrong PIN counts toward the server's lockout).
    final AuthSession session;
    try {
      session = await _signIn(probeClient, mode, signInAs);
    } on AccountLockedException catch (e) {
      return SwitchResult.failure('login', loginFailureText(e));
    } on InvalidCredentialsException catch (e) {
      return SwitchResult.failure('login', loginFailureText(e));
    } on UnauthorizedException catch (e) {
      return SwitchResult.failure('login', 'Sign-in rejected: ${e.message}');
    } on ApiException catch (e) {
      return SwitchResult.failure('login', 'Sign-in failed: ${e.message}');
    } catch (e) {
      return SwitchResult.failure('login', 'Sign-in failed: $e');
    }
    if (session.token == null) {
      return const SwitchResult.failure(
          'login', 'Sign-in failed: the server returned no session');
    }

    // ── Both steps passed: now (and only now) change anything. ────────────
    // Best effort: end the old session on the old server while its address is
    // still active. Failure here doesn't matter.
    final oldToken = authService.token;
    final wasDevice = authService.isDeviceSession;
    if (oldToken != null) {
      try {
        if (wasDevice) {
          await activeApi
              .kioskLogout(oldToken)
              .timeout(const Duration(seconds: 3));
        } else {
          await activeApi.logout(oldToken).timeout(const Duration(seconds: 3));
        }
      } catch (_) {}
    }

    await authService.resetForServerChange();
    await storeConfigService.resetForServerChange();
    await LocalPrefs.clearLandingCacheMeta();
    order.reset();

    await _record(customEnabled, custom); // flips the active URL + notifies
    await authService.adoptSession(session);

    // Refresh what the new server owns. Both use the shared client, which now
    // resolves to the new address.
    final config = await activeApi.getConfig();
    authService.applyConfig(config);
    await authService.resolveDefaultStore(activeApi);

    return SwitchResult.success(customEnabled
        ? 'Connected to $targetUrl'
        : 'Back on the app default ($targetUrl)');
  }

  static Future<void> _record(bool enabled, CustomConnection custom) =>
      AppConfig.connection.save(enabled: enabled, custom: custom);

  static Future<AuthSession> _signIn(
      ApiClient api, BrowsingMode mode, SwitchCredentials? c) {
    switch (mode) {
      case BrowsingMode.kiosk:
        return api.kioskLogin(c!.username.trim(), c.secret);
      case BrowsingMode.normal:
        return api.login(c!.username.trim(), c.secret,
            sessionProperties: {'mode': mode.name.toUpperCase()});
      case BrowsingMode.shopping:
        return api.guest();
    }
  }
}
