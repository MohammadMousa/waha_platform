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
      storeConfigService.setStoreId(effectiveDefault, persist: false);
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
        // Fall through to resolveDefaultStore below — _applySession sets
        // storeId from the session but never sets storeCurrency (it's not in
        // the auth response). Without resolveDefaultStore, currency stays null
        // after every restart for logged-in users and the cart shows no symbol.
      } on UnauthorizedException {
        // Falls through to re-authenticate with cached credentials.
      } catch (_) {
        // Network/timeout — keep token but still resolve currency if possible.
        token = cachedToken;
        notifyListeners();
      }
    }

    if (token == null && cachedUsername != null && cachedPassword != null) {
      try {
        await login(api, cachedUsername, cachedPassword);
        // Fall through to resolveDefaultStore — login() doesn't set currency.
      } catch (_) {
        await LocalPrefs.clearAuthToken();
        await LocalPrefs.clearAuthCredentials();
      }
    }

    if (token == null && mode == BrowsingMode.shopping) {
      try {
        await loginAsGuest(api);
      } catch (_) {
        // Backend unreachable — stay logged out, surface error at checkout.
      }
    }

    // Always ensure store currency is resolved — it's in-memory only and
    // lost on every restart regardless of auth state.
    await resolveDefaultStore(api);
  }

  /// Fetches the server's default store list and resolves currency in-memory.
  /// Prefers the store already selected (from LocalPrefs or session) so it
  /// doesn't overwrite the user's configured default. Never writes to LocalPrefs.
  Future<void> resolveDefaultStore(ApiClient api) async {
    if (storeConfigService.storeCurrency != null) return;
    try {
      final stores = await api.getStores();
      if (stores.isNotEmpty) {
        final currentId = storeConfigService.storeId;
        final candidates =
            currentId != null ? stores.where((s) => s.id == currentId) : null;
        final s = (candidates != null && candidates.isNotEmpty)
            ? candidates.first
            : stores.first;
        storeConfigService.applySessionStore(s.id, name: s.name, currency: s.currency);
      }
    } catch (_) {
      // Non-fatal — user hits StorePicker if they try to browse with no store.
    }
  }
}

final authService = AuthService();
