import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/store.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../services/geidea_terminal_bridge.dart';
import '../services/local_prefs.dart';
import 'browsing_mode_service.dart';
import 'locale_service.dart';
import 'permission_service.dart';
import 'store_config_service.dart';

/// Customer identity — Bearer-token auth, opaque token looked up
/// server-side. Kiosk: operator provisions device once, auto-login
/// on each launch. Shopping: guest() called first time no usable
/// cached session exists. Normal: anonymous until checkout gates it.
class AuthService extends ChangeNotifier {
  String? token;
  int? userId;
  int? deviceId;
  String? username;
  int? sessionStoreId;
  int? organizationId;
  int? defaultStoreId;
  String? mode;

  bool get isLoggedIn => token != null;
  bool get hasSelectedStore => sessionStoreId != null;
  bool get isDeviceSession => deviceId != null;

  void applyConfig(Map<String, String> config) {
    final appNameJson = config['appName'];
    if (appNameJson != null && appNameJson.isNotEmpty) {
      try {
        final nameMap = jsonDecode(appNameJson) as Map<String, dynamic>;
        storeConfigService.setAppName(nameMap);
      } catch (_) {}
    }
  }

  void _applySession(AuthSession session, {String? tokenOverride}) {
    if (tokenOverride != null) token = tokenOverride;
    userId = session.userId;
    deviceId = session.deviceId;
    username = session.username;
    sessionStoreId = session.storeId;
    if (session.organizationId != null) {
      organizationId = session.organizationId;
      // Native (AutoLogUploader) has no other way to learn this — best
      // effort, diagnostics only.
      GeideaTerminalBridge.instance.setOrgId(organizationId);
    }
    defaultStoreId = session.defaultStoreId;
    mode = session.mode;

    // Read defaultStoreId from properties map (takes precedence over top-level field,
    // since the backend is moving toward the properties map as the canonical source).
    final propsDefaultStore = session.properties?['defaultStoreId'];
    final defaultFromProps =
        propsDefaultStore != null ? int.tryParse(propsDefaultStore) : null;
    // Falls back to the session's own bound storeId last — the Kiosk device
    // login response has no defaultStoreId at all (a device is pinned to
    // one store, not "defaulted" to one), so without this fallback a fresh
    // device login would leave storeConfigService (and therefore the
    // displayed currency/name) resolving to whichever store happens to
    // come first from GET /api/stores, not the device's own store.
    final effectiveDefault =
        defaultFromProps ?? session.defaultStoreId ?? session.storeId;
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

  // Waha Rules (Auth): no password stored locally, for any login type —
  // only the token, validated via GET /api/auth/me on the next start (see
  // resolveStartupAuth). A rejected/expired token means signing in again
  // by hand, never a silent replay of a cached password.
  Future<void> register(ApiClient api, String username, String password) async {
    final session = await api.register(username, password);
    _applySession(session, tokenOverride: session.token);
    await LocalPrefs.setAuthToken(session.token!);
    notifyListeners();
  }

  Future<void> login(ApiClient api, String username, String password) async {
    final currentMode = browsingModeService.mode.name.toUpperCase();
    final session = await api
        .login(username, password, sessionProperties: {'mode': currentMode});
    _applySession(session, tokenOverride: session.token);
    await LocalPrefs.setAuthToken(session.token!);
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

  /// Device identity for Kiosk mode — a fixed terminal login, not a
  /// per-customer one. The PIN is never cached (Waha Rules, Auth — no
  /// password/PIN stored locally, for any login type); only the resulting
  /// token is, same as login() below. resolveStartupAuth validates that
  /// token via GET /api/kiosk/auth/me on every launch instead of replaying
  /// the PIN — this only runs from a human typing it on the Device Login
  /// screen, or that startup token check coming back rejected.
  Future<void> loginKiosk(
      ApiClient api, String username, String pinCode) async {
    final session = await api.kioskLogin(username, pinCode);
    _applySession(session, tokenOverride: session.token);
    await LocalPrefs.setAuthToken(session.token!);
    await LocalPrefs.setKioskUsernameCache(username);
    notifyListeners();
  }

  /// Explicit user-initiated logout. Not reachable from locked Kiosk/
  /// Shopping sessions (those routes are outside the allowlists) — Kiosk
  /// devices stay logged in permanently once provisioned; see
  /// resolveStartupAuth.
  Future<void> logout(ApiClient api) async {
    final t = token;
    final wasDeviceSession = isDeviceSession;
    _clearSessionMemory();
    await LocalPrefs.clearAuthToken();
    await LocalPrefs.clearAuthCredentials();
    await LocalPrefs.clearKioskCredentials();
    notifyListeners();
    if (t != null) {
      try {
        if (wasDeviceSession) {
          await api.kioskLogout(t);
        } else {
          await api.logout(t);
        }
      } catch (_) {
        // Already logged out locally — server-side failure doesn't undo that.
      }
    }
  }

  void _clearSessionMemory() {
    token = null;
    userId = null;
    deviceId = null;
    username = null;
    sessionStoreId = null;
    defaultStoreId = null;
    mode = null;
    permissionService.clear();
  }

  /// Drops the session and every locally cached credential because they
  /// belong to a server the app is leaving. No server call — the caller
  /// does any best-effort logout on the old server first.
  Future<void> resetForServerChange() async {
    _clearSessionMemory();
    await LocalPrefs.clearAuthToken();
    await LocalPrefs.clearAuthCredentials();
    await LocalPrefs.clearKioskCredentials();
    notifyListeners();
  }

  /// Takes over a session that was just created on the new server by a
  /// separate client. Persists the token only — never the username/PIN or
  /// password the operator typed.
  Future<void> adoptSession(AuthSession session) async {
    _applySession(session, tokenOverride: session.token);
    await LocalPrefs.setAuthToken(session.token!);
    notifyListeners();
  }

  Future<void> selectStore(ApiClient api, int storeId) async {
    final t = token;
    if (t == null) throw StateError('selectStore() called while logged out');
    final currentMode = browsingModeService.mode.name.toUpperCase();
    final session = await api
        .selectStore(t, storeId, sessionProperties: {'mode': currentMode});
    _applySession(session);
    notifyListeners();
  }

  /// Full startup auth resolution:
  ///   Kiosk: a separate identity domain entirely (POST /api/kiosk/auth/login,
  ///     device/PIN — see docs/roles-permissions.md), but validated the SAME
  ///     way as Normal/Shopping below: try the cached TOKEN first via GET
  ///     /api/kiosk/auth/me, never a cached PIN (Waha Rules, Auth — no
  ///     password/PIN stored locally, for any login type). A rejected/
  ///     missing token leaves the device logged out; the router gates every
  ///     route behind isDeviceSession until a human logs in on the Device
  ///     Login screen. Never anonymous, never the customer /api/auth/*
  ///     domain below.
  ///   Normal/Shopping:
  ///     1. Try cached token via GET /api/auth/me.
  ///     2. If rejected, re-authenticate with cached credentials.
  ///     3. Shopping mode: mint a fresh guest account via POST /api/auth/guest.
  ///        Normal: stay logged out (anonymous browsing is allowed there).
  ///   Always: if no store configured after auth, resolve from server default.
  Future<void> resolveStartupAuth(ApiClient api, BrowsingMode mode) async {
    // Load public system config (appName, etc.) before any auth so the title
    // shows immediately even in kiosk mode with no cached login.
    applyConfig(await api.getConfig());

    // Same reasoning as the kiosk PIN purge below — a normal/shopping user
    // logged in before this rule was enforced may still be carrying a
    // plaintext cached password, and a valid never-expiring token means
    // they may never hit logout() to trigger the existing cleanup there.
    await LocalPrefs.clearAuthCredentials();

    if (mode == BrowsingMode.kiosk) {
      // One-time-per-launch purge of a plaintext PIN a device provisioned
      // before this rule was enforced may still be carrying — an
      // already-logged-in kiosk may never hit logout() otherwise. Cheap,
      // safe to call every start (no-ops once the key is gone), and
      // deliberately doesn't touch the harmless username cache below.
      await LocalPrefs.purgeLegacyKioskPin();
      final cachedToken = LocalPrefs.authToken;
      if (cachedToken != null) {
        try {
          final session =
              await api.kioskMe(cachedToken).timeout(const Duration(seconds: 5));
          token = cachedToken;
          _applySession(session);
          notifyListeners();
        } on UnauthorizedException {
          // Really rejected (revoked/invalidated), not just unreachable —
          // drop it. The router sends the device to Routes.kioskLogin for a
          // human to log in with the PIN; never auto-retried from a cached
          // secret.
          await LocalPrefs.clearAuthToken();
        } catch (_) {
          // Network/timeout — keep the token, optimistic it's still valid;
          // same tradeoff Normal/Shopping below makes.
          token = cachedToken;
          notifyListeners();
        }
      }
      await resolveDefaultStore(api);
      await _applyStartupLanguageSeed(api);
      return;
    }

    final cachedToken = LocalPrefs.authToken;

    if (cachedToken != null) {
      try {
        final session =
            await api.me(cachedToken).timeout(const Duration(seconds: 5));
        token = cachedToken;
        _applySession(session);
        notifyListeners();
        // Fall through to resolveDefaultStore below — _applySession sets
        // storeId from the session but never sets storeCurrency (it's not in
        // the auth response). Without resolveDefaultStore, currency stays null
        // after every restart for logged-in users and the cart shows no symbol.
      } on UnauthorizedException {
        // Really rejected (revoked/invalidated), not just unreachable —
        // drop it. Never re-authenticated from a cached password (Waha
        // Rules, Auth — no credentials stored locally, any login type):
        // Shopping falls through to a fresh guest account below, Normal
        // stays logged out until the person signs in again by hand.
        await LocalPrefs.clearAuthToken();
      } catch (_) {
        // Network/timeout — keep token but still resolve currency if possible.
        token = cachedToken;
        notifyListeners();
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
    await _applyStartupLanguageSeed(api);
  }

  /// Applies the org's default_language right at startup, as soon as
  /// organizationId is known (from the login just above) — NOT on the
  /// Landing screen's later periodic timer, which is deliberately delayed to
  /// avoid piling onto this same startup network burst. That delay makes
  /// sense for the (heavier) landing-page-refresh check; it does not make
  /// sense for one small language field, so this reads it separately, here,
  /// right after login.
  Future<void> _applyStartupLanguageSeed(ApiClient api) async {
    final orgId = organizationId;
    if (orgId == null) return;
    try {
      applyLanguageSeed(await api.getConfig(orgId: orgId));
    } catch (_) {
      // Network hiccup — the periodic check on Landing will pick it up later.
    }
  }

  /// Fetches the server's store list and resolves currency + display name in-memory.
  /// Honors the preferred store (from LocalPrefs). If it's a non-public store
  /// (parent/admin node), falls back to the admin store list when logged in.
  /// Never writes to LocalPrefs.
  Future<void> resolveDefaultStore(ApiClient api) async {
    if (storeConfigService.storeCurrency != null) return;
    try {
      final preferredId = storeConfigService.storeId;
      List<Store> stores = await api.getStores();

      Store? preferred = preferredId != null
          ? stores.where((s) => s.id == preferredId).firstOrNull
          : null;

      // Preferred store not in public list (e.g. admin/parent node) — try admin list.
      if (preferred == null && preferredId != null && token != null) {
        try {
          final adminStores = await api.getAdminStores(token!);
          preferred = adminStores.where((s) => s.id == preferredId).firstOrNull;
          if (stores.isEmpty) stores = adminStores;
        } catch (_) {}
      }

      final Store? s = preferred ?? (stores.isNotEmpty ? stores.first : null);
      if (s != null) {
        storeConfigService.applySessionStore(s.id,
            displayName: s.displayName?.cast<String, dynamic>(),
            slug: s.name,
            currency: s.currency);
      }
    } catch (_) {
      // Non-fatal — user hits StorePicker if they try to browse with no store.
    }
  }
}

final authService = AuthService();
