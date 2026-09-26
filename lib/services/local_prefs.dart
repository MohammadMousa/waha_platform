import 'package:shared_preferences/shared_preferences.dart';

import '../config/connection_settings.dart' show CustomConnection;

/// Thin persistence facade — every runtime-configurable service
/// (BrowsingModeService, StoreConfigService, LocaleService,
/// KioskTimerConfig, AuthService) goes through this instead of
/// talking to SharedPreferences directly, so key names live in one place.
///
/// Must be initialized (awaited) before runApp — see main.dart. This
/// exists specifically because self-service devices reboot: a kiosk that
/// loses power and comes back up needs to resume in whatever mode/store/
/// timers it was configured for, not silently revert to defaults. In
/// memory only was fine for a demo running in one sitting; it's not fine
/// for anything meant to survive unattended.
class LocalPrefs {
  LocalPrefs._();
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError(
          'LocalPrefs.init() must be awaited before use — see main.dart');
    }
    return prefs;
  }

  static const _kMode = 'waha.browsing_mode';
  static const _kStoreId = 'waha.store_id';
  static const _kDefaultStoreId = 'waha.default_store_id';
  static const _kLocale = 'waha.locale';
  static const _kAuthToken = 'waha.auth_token';
  static const _kAuthUsername = 'waha.auth_username';
  static const _kAuthPassword = 'waha.auth_password';
  static const _kBeforeWarn = 'waha.kiosk_before_warn_s';
  static const _kBeforeCountdown = 'waha.kiosk_before_countdown_s';
  static const _kAfterWarn = 'waha.kiosk_after_warn_s';
  static const _kAfterCountdown = 'waha.kiosk_after_countdown_s';

  static String? get mode => _p.getString(_kMode);
  static Future<void> setMode(String value) => _p.setString(_kMode, value);

  static int? get storeId => _p.getInt(_kStoreId);
  static Future<void> setStoreId(int value) => _p.setInt(_kStoreId, value);

  static Future<void> clearStoreIds() async {
    await _p.remove(_kStoreId);
    await _p.remove(_kDefaultStoreId);
  }

  /// Forgets the cached landing pages' hashes/URLs so the next launch of any
  /// landing page downloads fresh from whichever server is now active.
  static Future<void> clearLandingCacheMeta() async {
    for (final k in _p.getKeys().toList()) {
      if (k.startsWith('waha.landing_hash.') ||
          k.startsWith('waha.landing_res_url.') ||
          k == _kLandingNormalKey) {
        await _p.remove(k);
      }
    }
  }

  static int? get defaultStoreId => _p.getInt(_kDefaultStoreId);
  static Future<void> setDefaultStoreId(int value) =>
      _p.setInt(_kDefaultStoreId, value);

  static const _kKioskUsername = 'waha.kiosk_username';
  static String? get kioskUsername => _p.getString(_kKioskUsername);
  static Future<void> setKioskUsername(String value) =>
      _p.setString(_kKioskUsername, value);

  static const _kKioskPin = 'waha.kiosk_pin';

  /// Cached device username/PIN — the Kiosk-mode equivalent of
  /// authUsername/authPassword above (same plaintext-storage tradeoff:
  /// this is the device's own credential, re-used to re-authenticate on
  /// every app start since there's no session-check endpoint for device
  /// sessions, only login). Deliberately separate from setKioskUsername
  /// above, which is unrelated leftover state from IdentityService.
  static String? get kioskPin => _p.getString(_kKioskPin);
  static Future<void> setKioskCredentials(String username, String pin) async {
    await _p.setString(_kKioskUsername, username);
    await _p.setString(_kKioskPin, pin);
  }

  static Future<void> clearKioskCredentials() async {
    await _p.remove(_kKioskUsername);
    await _p.remove(_kKioskPin);
  }

  static String? get locale => _p.getString(_kLocale);
  static Future<void> setLocale(String value) => _p.setString(_kLocale, value);

  /// The customer auth session token — persisted so a login survives an
  /// app restart. Cleared on logout, not just overwritten, since `remove`
  /// and `setString(null)` aren't the same thing in SharedPreferences.
  static String? get authToken => _p.getString(_kAuthToken);
  static Future<void> setAuthToken(String value) =>
      _p.setString(_kAuthToken, value);
  static Future<void> clearAuthToken() => _p.remove(_kAuthToken);

  /// Cached username/password, per explicit MVP direction: no refresh-
  /// token mechanism exists yet, so re-authenticating with the cached
  /// credentials is the specified fallback when a cached token is
  /// rejected or expired. Worth flagging plainly rather than burying it:
  /// this means a plaintext password sits in SharedPreferences, which on
  /// Android is not secure storage (readable if the device is rooted).
  /// Accepted as an explicit MVP tradeoff, not an oversight — but worth
  /// moving to flutter_secure_storage (Keychain/Keystore-backed) before
  /// this goes anywhere near a real deployment.
  static String? get authUsername => _p.getString(_kAuthUsername);
  static String? get authPassword => _p.getString(_kAuthPassword);
  static Future<void> setAuthCredentials(
      String username, String password) async {
    await _p.setString(_kAuthUsername, username);
    await _p.setString(_kAuthPassword, password);
  }

  static Future<void> clearAuthCredentials() async {
    await _p.remove(_kAuthUsername);
    await _p.remove(_kAuthPassword);
  }

  static int? get beforeWarnSeconds => _p.getInt(_kBeforeWarn);
  static int? get beforeCountdownSeconds => _p.getInt(_kBeforeCountdown);
  static int? get afterWarnSeconds => _p.getInt(_kAfterWarn);
  static int? get afterCountdownSeconds => _p.getInt(_kAfterCountdown);

  static Future<void> setTimers({
    required int beforeWarnSeconds,
    required int beforeCountdownSeconds,
    required int afterWarnSeconds,
    required int afterCountdownSeconds,
  }) async {
    await _p.setInt(_kBeforeWarn, beforeWarnSeconds);
    await _p.setInt(_kBeforeCountdown, beforeCountdownSeconds);
    await _p.setInt(_kAfterWarn, afterWarnSeconds);
    await _p.setInt(_kAfterCountdown, afterCountdownSeconds);
  }

  // Dev-tools cluster visibility. Until the operator explicitly shows/hides
  // it (which persists from then on and always wins over this), defaults to
  // whatever this build was compiled with: visible if ENABLE_SIMULATOR=true
  // (that's a dev/test build in the first place — no reason to also make it
  // hunt for a secret 10-tap gesture just to see its own dev tools), hidden
  // otherwise (a real release build, where dev tools should not be casually
  // stumbled into). Reads the dart-define directly rather than importing
  // AppConfig, which itself imports this file.
  static const _kSimDevToolsVisible = 'waha.sim_dev_tools_visible';
  static const _kEnableSimulatorCompileFlag =
      bool.fromEnvironment('ENABLE_SIMULATOR', defaultValue: false);
  static bool get simDevToolsVisible =>
      _p.getBool(_kSimDevToolsVisible) ?? _kEnableSimulatorCompileFlag;
  static Future<void> setSimDevToolsVisible(bool value) =>
      _p.setBool(_kSimDevToolsVisible, value);

  // Whether the Settings screen's "Developer Tools" section has been
  // unlocked (10-tap gesture). Persisted separately from
  // simDevToolsVisible (the floating overlay cluster) so it stays revealed
  // across visits to Settings until explicitly hidden via its own eye
  // button, instead of re-locking every time the screen is rebuilt.
  static const _kDevToolsUnlocked = 'waha.dev_tools_unlocked';
  static bool get devToolsUnlocked => _p.getBool(_kDevToolsUnlocked) ?? false;
  static Future<void> setDevToolsUnlocked(bool value) =>
      _p.setBool(_kDevToolsUnlocked, value);

  // Runtime override that turns on the simulator dev-tools cluster even in a
  // build compiled with ENABLE_SIMULATOR=false, once the operator has
  // already unlocked Settings' Developer Tools panel via the 10-tap gesture.
  // Kept as its own flag (not folded into AppConfig.simulatorAvailable)
  // deliberately — that flag's own doc comment warns it must stay
  // compile-time-only so it can never leak app-wide (e.g. the cart screen's
  // own 10-tap reveal gesture). This override only ever affects whether the
  // SimulatorOverlay widget itself renders, nothing else.
  static const _kSimulatorForceEnabled = 'waha.simulator_force_enabled';
  static bool get simulatorForceEnabled =>
      _p.getBool(_kSimulatorForceEnabled) ?? false;
  static Future<void> setSimulatorForceEnabled(bool value) =>
      _p.setBool(_kSimulatorForceEnabled, value);

  // Footer toast after a successful camera-scan add. Off by default — the
  // scan sound already confirms success, so the toast is opt-in extra
  // feedback rather than something shown to every customer.
  static const _kShowScanSuccessToast = 'waha.show_scan_success_toast';
  static bool get showScanSuccessToast =>
      _p.getBool(_kShowScanSuccessToast) ?? false;
  static Future<void> setShowScanSuccessToast(bool value) =>
      _p.setBool(_kShowScanSuccessToast, value);

  // Cart's bottom nav bar (Home/Cart tabs) is hidden by default in Kiosk mode
  // — the reference design has nothing below the summary card and the
  // Buy&Pay/Cancel buttons there. This is an explicit opt-in to bring it back
  // for a deployment that wants it.
  static const _kShowCartMenuInKiosk = 'waha.show_cart_menu_kiosk';
  static bool get showCartMenuInKiosk =>
      _p.getBool(_kShowCartMenuInKiosk) ?? false;
  static Future<void> setShowCartMenuInKiosk(bool value) =>
      _p.setBool(_kShowCartMenuInKiosk, value);

  // On by default: KioskIdleGuard's inactivity-driven redirect-home was
  // suspected as an ongoing source of Navigator-corruption crashes on real
  // hardware (see git history on kiosk_idle_guard.dart), so this defaulted
  // off while that was unconfirmed. Now confirmed working fine on real
  // kiosk hardware — the checkbox stays as a manual fallback in case a
  // specific device needs it disabled again, but the default is trusted.
  static const _kKioskTimersEnabled = 'waha.kiosk_timers_enabled';
  static bool get kioskTimersEnabled =>
      _p.getBool(_kKioskTimersEnabled) ?? true;
  static Future<void> setKioskTimersEnabled(bool value) =>
      _p.setBool(_kKioskTimersEnabled, value);

  // Diagnostic-only, temporary: gates TraceLog (see lib/services/trace_log.dart)
  // and MainActivity.logTrace's native-side writes — false by default, since
  // this shouldn't write to disk forever on every kiosk in the field. Two
  // ways to turn it on: this persisted Settings toggle (works on a device
  // already installed, no rebuild needed), or a `--dart-define=LOGGING=true`
  // build (see main.dart, which seeds this same persisted value from that
  // define on first run — from then on this toggle is the durable control).
  // Remove alongside the rest of the trace-logging system once no longer needed.
  static const _kLoggingEnabled = 'waha.logging_enabled';
  static bool get loggingEnabled => _p.getBool(_kLoggingEnabled) ?? false;
  static Future<void> setLoggingEnabled(bool value) =>
      _p.setBool(_kLoggingEnabled, value);

  // Which shortcut buttons show in the simulator cluster — 'home', 'settings',
  // 'camera', 'productScan' (manual barcode entry/cached-code fire),
  // 'browse'. Null (never saved) means "use the default set" rather than
  // "empty" — see SimulatorService for what that default is; not baked in
  // here so the default can evolve without a stale empty list looking
  // identical to an intentional "hide everything" choice.
  static const _kSimPinnedButtons = 'waha.sim_pinned_buttons';
  static List<String>? get simPinnedButtons =>
      _p.getStringList(_kSimPinnedButtons);
  static Future<void> setSimPinnedButtons(List<String> ids) =>
      _p.setStringList(_kSimPinnedButtons, ids);

  // Whether the session-info footer (username/store slug/host/app-mode
  // strip) is showing. A real, persisted setting — toggleable from the
  // simulator cluster's own button AND from a switch in Settings, both
  // reading/writing this same value, not just an in-memory simulator flag.
  // Off by default, same as the other diagnostic-only toggles here.
  static const _kShowSessionFooter = 'waha.show_session_footer';
  static bool get showSessionFooter => _p.getBool(_kShowSessionFooter) ?? false;
  static Future<void> setShowSessionFooter(bool value) =>
      _p.setBool(_kShowSessionFooter, value);

  static const _kSimProductCodes = 'waha.sim_product_codes';
  static List<String> get simProductCodes =>
      _p.getStringList(_kSimProductCodes) ?? [];
  static Future<void> setSimProductCodes(List<String> codes) =>
      _p.setStringList(_kSimProductCodes, codes);

  // How long the Kiosk waits for a card-present terminal (Geidea) response
  // before giving up and cancelling its own session — a client-side
  // watchdog, deliberately kept well under the backend's fixed 90s
  // PENDING→TIMEOUT window (TerminalSessionService.java) so the Kiosk
  // always cancels cleanly before that window can lapse out from under it.
  // Settings screen clamps the value it accepts to enforce that margin.
  static const _kTerminalTimeout = 'waha.terminal_timeout_s';
  static const int defaultTerminalTimeoutSeconds = 60;
  static int get terminalTimeoutSeconds =>
      _p.getInt(_kTerminalTimeout) ?? defaultTerminalTimeoutSeconds;
  static Future<void> setTerminalTimeoutSeconds(int value) =>
      _p.setInt(_kTerminalTimeout, value);

  // Auto-cache: when on, every code the simulator fires (tap, long-press
  // manual entry, camera-via-simulator) gets appended to simProductCodes
  // automatically, up to simCacheLimit. Off by default — opt-in, since it
  // changes the saved-codes list as a side effect of just using the
  // simulator rather than requiring the explicit editor screen.
  static const _kSimAutoCache = 'waha.sim_auto_cache';
  static bool get simAutoCache => _p.getBool(_kSimAutoCache) ?? false;
  static Future<void> setSimAutoCache(bool value) =>
      _p.setBool(_kSimAutoCache, value);

  static const _kSimCacheLimit = 'waha.sim_cache_limit';
  static int get simCacheLimit => _p.getInt(_kSimCacheLimit) ?? 10;
  static Future<void> setSimCacheLimit(int value) =>
      _p.setInt(_kSimCacheLimit, value);

  // Custom Connection — an explicit override of the project/build default
  // server. The fields are kept while the switch is OFF and change only when
  // the user edits them. Persisted so kiosk devices survive reboots.
  static const _kCustomConnEnabled = 'waha.custom_conn_enabled';
  // Screen factor (UI scaling): 'auto' | 'manual', plus the manual machine.
  static const _kScreenFactorMode = 'waha.screen_factor_mode';
  static const _kScreenFactorMachine = 'waha.screen_factor_machine';
  static String get screenFactorMode =>
      _p.getString(_kScreenFactorMode) ?? 'auto';
  static Future<void> setScreenFactorMode(String v) =>
      _p.setString(_kScreenFactorMode, v);
  static String get screenFactorMachine =>
      _p.getString(_kScreenFactorMachine) ?? 'largeKiosk';
  static Future<void> setScreenFactorMachine(String v) =>
      _p.setString(_kScreenFactorMachine, v);

  static const _kCustomConnScheme = 'waha.custom_conn_scheme';
  static const _kCustomConnHost = 'waha.custom_conn_host';
  static const _kCustomConnPort = 'waha.custom_conn_port';
  static const _kCustomConnBasePath = 'waha.custom_conn_base_path';

  static bool get customConnectionEnabled =>
      _p.getBool(_kCustomConnEnabled) ?? false;
  static Future<void> setCustomConnectionEnabled(bool value) =>
      _p.setBool(_kCustomConnEnabled, value);
  static String get customConnScheme =>
      _p.getString(_kCustomConnScheme) ?? 'http';
  static String get customConnHost => _p.getString(_kCustomConnHost) ?? '';
  static int? get customConnPort => _p.getInt(_kCustomConnPort);
  static String get customConnBasePath =>
      _p.getString(_kCustomConnBasePath) ?? '';

  static Future<void> setCustomConnection(CustomConnection c) async {
    await _p.setString(_kCustomConnScheme, c.scheme);
    await _p.setString(_kCustomConnHost, c.host);
    if (c.port == null) {
      await _p.remove(_kCustomConnPort);
    } else {
      await _p.setInt(_kCustomConnPort, c.port!);
    }
    await _p.setString(_kCustomConnBasePath, c.basePath);
  }

  // Old single-URL setting, read only by the one-time migration.
  static const _kLegacyApiBaseUrl = 'waha.api_base_url';
  static String? get legacyApiBaseUrl => _p.getString(_kLegacyApiBaseUrl);
  static Future<void> clearLegacyApiBaseUrl() => _p.remove(_kLegacyApiBaseUrl);

  // Landing page cache — hash only; HTML bytes live in LandingCache files.
  // Separate key per page (KIOSK_LANDING, SHOPPING_LANDING, CLIENT_LANDING, ADMIN_LANDING).
  static String? landingHash(String pageKey) =>
      _p.getString('waha.landing_hash.$pageKey');
  static Future<void> setLandingHash(String pageKey, String hash) =>
      _p.setString('waha.landing_hash.$pageKey', hash);

  // Resource URL for each landing page key — relative path like
  // /resource/waha/pages/KIOSK_LANDING.html — stored so the WebView can load
  // via loadRequest() on the next cold start without waiting for the API.
  static String? landingResourceUrl(String pageKey) =>
      _p.getString('waha.landing_res_url.$pageKey');
  static Future<void> setLandingResourceUrl(String pageKey, String url) =>
      _p.setString('waha.landing_res_url.$pageKey', url);

  // Which page key was last used for BrowsingMode.normal — either
  // 'ADMIN_LANDING' or 'CLIENT_LANDING'. Saved after auth resolves so the
  // correct page is served on the very next cold start without waiting.
  static const _kLandingNormalKey = 'waha.landing_normal_key';
  static String? get landingNormalKey => _p.getString(_kLandingNormalKey);
  static Future<void> setLandingNormalKey(String key) =>
      _p.setString(_kLandingNormalKey, key);
}
