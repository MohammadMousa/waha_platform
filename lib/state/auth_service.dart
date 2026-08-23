import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../services/local_prefs.dart';
import 'browsing_mode_service.dart';
import 'permission_service.dart';
import 'store_config_service.dart';

/// Customer identity — Bearer-token auth, opaque token looked up
/// server-side. Kiosk: operator provisions device once, auto-login
/// on each launch. Shopping: guest() called first time no usable
/// cached session exists. Normal: anonymous until checkout gates it.
class AuthService extends ChangeNotifier {
  String? token;
  int? userId;
  String? username;
  int? sessionStoreId;
  int? defaultStoreId;
  String? mode;

  bool get isLoggedIn => token != null;
  bool get hasSelectedStore => sessionStoreId != null;

  void _applySession(AuthSession session, {String? tokenOverride}) {
    if (tokenOverride != null) token = tokenOverride;
    userId = session.userId;
    username = session.username;
    sessionStoreId = session.storeId;
    defaultStoreId = session.defaultStoreId;
    mode = session.mode;

    // Read defaultStoreId from properties map (takes precedence over top-level field,
    // since the backend is moving toward the properties map as the canonical source).
    final propsDefaultStore = session.properties?['defaultStoreId'];
    final defaultFromProps = propsDefaultStore != null
        ? int.tryParse(propsDefaultStore)
        : null;
    final effectiveDefault = defaultFromProps ?? session.defaultStoreId;
    if (storeConfigService.storeId == null && effectiveDefault != null) {
      storeConfigService.setStoreId(effectiveDefault);
    }

    // Read app name from properties and store it for the UI.
    final appNameJson = session.properties?['appName'];
    if (appNameJson != null) {
      try {
        final nameMap = jsonDecode(appNameJson) as Map<String, dynamic>;
        storeConfigService.setAppName(nameMap);
      } catch (_) {}
    }

    // Cache resolved permissions for this user+store context.
    permissionService.update(session.permissions);
  }

  Future<void> register(ApiClient api, String username, String password) async {
    final session = await api.register(username, password);
    _applySession(session, tokenOverride: session.token);
    await LocalPrefs.setAuthToken(session.token!);
    await LocalPrefs.setAuthCredentials(username, password);
    notifyListeners();
  }

  Future<void> login(ApiClient api, String username, String password) async {
    final currentMode = browsingModeService.mode.name.toUpperCase();
    final session = await api.login(username, password,
        sessionProperties: {'mode': currentMode});
    _applySession(session, tokenOverride: session.token);
    await LocalPrefs.setAuthToken(session.token!);
    await LocalPrefs.setAuthCredentials(username, password);
    notifyListeners();
  }

  /// Creates a throwaway Shopping guest session. No credentials cached —
  /// guest accounts are ephemeral and recreated fresh each time.
  Future<void> loginAsGuest(ApiClient api) async {
    final session = await api.guest();
    _applySession(session, tokenOverride: session.token);
    await LocalPrefs.setAuthToken(session.token!);
    // No credentials to cache — guest has no password we know.
    notifyListeners();
  }

  /// Explicit user-initiated logout. Not reachable from locked Kiosk/
  /// Shopping sessions (those routes are outside the allowlists).
  Future<void> logout(ApiClient api) async {
    final t = token;
    token = null;
    userId = null;
    username = null;
    sessionStoreId = null;
    defaultStoreId = null;
    mode = null;
    permissionService.clear();
    await LocalPrefs.clearAuthToken();
    await LocalPrefs.clearAuthCredentials();
    notifyListeners();
    if (t != null) {
      try {
        await api.logout(t);
      } catch (_) {
        // Already logged out locally — server-side failure doesn't undo that.
      }
    }
  }

  Future<void> selectStore(ApiClient api, int storeId) async {
    final t = token;
    if (t == null) throw StateError('selectStore() called while logged out');
    final currentMode = browsingModeService.mode.name.toUpperCase();
    final session = await api.selectStore(t, storeId,
        sessionProperties: {'mode': currentMode});
    _applySession(session);
    notifyListeners();
  }

  /// Full startup auth resolution:
  ///   1. Try cached token via GET /api/auth/me.
  ///   2. If rejected, re-authenticate with cached credentials.
  ///   3. Shopping mode: mint a fresh guest account via POST /api/auth/guest.
  ///      Normal/Kiosk: stay logged out.
  ///   4. Always: if no store configured after auth, resolve from server default.
  Future<void> resolveStartupAuth(ApiClient api, BrowsingMode mode) async {
    final cachedToken = LocalPrefs.authToken;
    final cachedUsername = LocalPrefs.authUsername;
    final cachedPassword = LocalPrefs.authPassword;

    if (cachedToken != null) {
      try {
        final session = await api.me(cachedToken).timeout(const Duration(seconds: 5));
        token = cachedToken;
        _applySession(session);
        notifyListeners();
        // _applySession already applies server defaultStoreId if storeConfigService
        // is unset — no need to call resolveDefaultStore separately here.
        return;
      } on UnauthorizedException {
        // Falls through to re-authenticate with cached credentials.
      } catch (_) {
        // Network/timeout — keep token rather than discarding a
        // possibly-still-valid session over a transient problem.
        token = cachedToken;
        notifyListeners();
        return;
      }
    }

    if (cachedUsername != null && cachedPassword != null) {
      try {
        await login(api, cachedUsername, cachedPassword);
        return;
      } catch (_) {
        await LocalPrefs.clearAuthToken();
        await LocalPrefs.clearAuthCredentials();
      }
    }

    if (mode == BrowsingMode.shopping) {
      try {
        await loginAsGuest(api);
        return;
      } catch (_) {
        // Backend unreachable — stay logged out, surface error at checkout.
      }
    }

    // Normal / Kiosk staying anonymous — ensure a store is configured so
    // browse/scan work without needing the user to pick one manually.
    await resolveDefaultStore(api);
  }

  /// Fetches the server's default store and sets it locally if no store is
  /// currently configured. Safe to call any time — no-op if already set.
  /// Used for anonymous users after logout and on first startup.
  Future<void> resolveDefaultStore(ApiClient api) async {
    // Always fetch even if storeId is known — currency may be null after restart.
    if (storeConfigService.storeId != null &&
        storeConfigService.storeCurrency != null) return;
    try {
      final stores = await api.getStores();
      if (stores.isNotEmpty) {
        final s = stores.first;
        storeConfigService.setStore(s.id, name: s.name, currency: s.currency);
      }
    } catch (_) {
      // Non-fatal — user hits StorePicker if they try to browse with no store.
    }
  }
}

final authService = AuthService();
