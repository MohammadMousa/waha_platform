import '../../services/local_prefs.dart';
import 'offline_level.dart';
import '../orders/local_order_service.dart';
import 'local_catalog.dart';

/// Where the app answers catalog and pricing questions from. When the server's
/// `offline_mode` property is on, [ApiClient] reads products, categories,
/// prices and quotes from the local database instead of the network. With the
/// property off nothing changes: every call goes to the server as before.
class OfflineMode {
  OfflineMode._();

  /// Set once at startup by the sync service (the local database).
  static LocalCatalog? catalog;

  /// Local orders (set together with [catalog]).
  static LocalOrderService? orders;

  /// The signed-in device's username, for the order's `username`.
  static String? Function() username = () => null;

  /// Terminal sessions opened locally: payment id -> order id. The payment
  /// dialog confirms or cancels by session id only.
  static final Map<String, String> sessionOrder = {};

  /// The last `offline_mode` value from /api/config (kept across restarts).
  static bool get active => catalog != null && LocalPrefs.offlineMode;

  /// `caching`: server first, saved copy only when the server cannot be
  /// reached (built in the next steps; today it changes nothing for reads).
  static bool get caching =>
      catalog != null && LocalPrefs.offlineLevel == OfflineLevel.caching;

  /// The `scan_disabled_products` rule: an inactive product is refused on
  /// scan and in the cart unless this is true.
  static bool get scanDisabledAllowed => LocalPrefs.scanDisabledProducts;
}
