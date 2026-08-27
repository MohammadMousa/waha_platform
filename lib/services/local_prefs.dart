import 'package:shared_preferences/shared_preferences.dart';

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
      throw StateError('LocalPrefs.init() must be awaited before use — see main.dart');
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

  static int? get defaultStoreId => _p.getInt(_kDefaultStoreId);
  static Future<void> setDefaultStoreId(int value) => _p.setInt(_kDefaultStoreId, value);

  static const _kKioskUsername = 'waha.kiosk_username';
  static String? get kioskUsername => _p.getString(_kKioskUsername);
  static Future<void> setKioskUsername(String value) => _p.setString(_kKioskUsername, value);

  static String? get locale => _p.getString(_kLocale);
  static Future<void> setLocale(String value) => _p.setString(_kLocale, value);

  /// The customer auth session token — persisted so a login survives an
  /// app restart. Cleared on logout, not just overwritten, since `remove`
  /// and `setString(null)` aren't the same thing in SharedPreferences.
  static String? get authToken => _p.getString(_kAuthToken);
  static Future<void> setAuthToken(String value) => _p.setString(_kAuthToken, value);
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
  static Future<void> setAuthCredentials(String username, String password) async {
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

  // Dev-tools cluster visibility. Defaults to false (hidden) when not set.
  static const _kSimDevToolsVisible = 'waha.sim_dev_tools_visible';
  static bool get simDevToolsVisible => _p.getBool(_kSimDevToolsVisible) ?? false;
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

  // Footer toast after a successful camera-scan add. Off by default — the
  // scan sound already confirms success, so the toast is opt-in extra
  // feedback rather than something shown to every customer.
  static const _kShowScanSuccessToast = 'waha.show_scan_success_toast';
  static bool get showScanSuccessToast => _p.getBool(_kShowScanSuccessToast) ?? false;
  static Future<void> setShowScanSuccessToast(bool value) =>
      _p.setBool(_kShowScanSuccessToast, value);

  static const _kSimProductCodes = 'waha.sim_product_codes';
  static List<String> get simProductCodes =>
      _p.getStringList(_kSimProductCodes) ?? [];
  static Future<void> setSimProductCodes(List<String> codes) =>
      _p.setStringList(_kSimProductCodes, codes);

  // Runtime API base URL — overrides platform default when set.
  // Persisted so kiosk devices survive reboots without reconfiguration.
  static const _kApiBaseUrl = 'waha.api_base_url';
  static String? get apiBaseUrl => _p.getString(_kApiBaseUrl);
  static Future<void> setApiBaseUrl(String value) => _p.setString(_kApiBaseUrl, value);
  static Future<void> clearApiBaseUrl() => _p.remove(_kApiBaseUrl);
}
