import '../../services/local_prefs.dart';
import '../../models/order.dart';
import '../../models/terminal_session.dart';
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

  /// Caching mode: orders the SERVER made and their open terminal sessions,
  /// remembered for the minutes around a payment. If the card is approved but
  /// the server cannot be told, these give the local record its numbers and
  /// keep the invoice screen showing the real lines and server number.
  /// (Memory only: a restart in the middle of a payment loses it, and the
  /// record is then built from the session alone.)
  static final Map<String, WahaOrder> serverOrders = {};
  static final Map<String, TerminalSession> serverSessions = {};

  static void remember<T>(Map<String, T> map, String key, T value) {
    map[key] = value;
    while (map.length > 20) {
      map.remove(map.keys.first);
    }
  }

  /// The signed-in device's username, for the order's `username`.
  static String? Function() username = () => null;

  /// Terminal sessions opened locally: payment id -> order id. The payment
  /// dialog confirms or cancels by session id only.
  static final Map<String, String> sessionOrder = {};

  /// The last `offline_mode` value from /api/config (kept across restarts).
  static bool get active => catalog != null && LocalPrefs.offlineMode;

  /// Orders made on this device live in the local database in `full` AND
  /// `caching` mode (in caching only when the server could not be reached at
  /// the time). Payment, session and status calls use this to tell a local
  /// order from a server one: a local order is handled locally, anything else
  /// goes to the server as before.
  static bool get localOrders =>
      catalog != null &&
      (LocalPrefs.offlineLevel == OfflineLevel.full ||
          LocalPrefs.offlineLevel == OfflineLevel.caching);

  /// `caching`: server first, saved copy only when the server cannot be
  /// reached (built in the next steps; today it changes nothing for reads).
  static bool get caching =>
      catalog != null && LocalPrefs.offlineLevel == OfflineLevel.caching;

  /// The `scan_disabled_products` rule: an inactive product is refused on
  /// scan and in the cart unless this is true.
  static bool get scanDisabledAllowed => LocalPrefs.scanDisabledProducts;
}
