import 'package:flutter/material.dart';

import '../models/account_user.dart';
import '../screens/browse_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/checkout_screen.dart';
import '../screens/account_edit_screen.dart';
import '../screens/accounts_screen.dart';
import '../screens/landing_editor_screen.dart';
import '../screens/odoo_admin_screen.dart';
import '../screens/invoice_screen.dart';
import '../screens/kiosk_login_screen.dart';
import '../screens/landing_screen.dart';
import '../screens/pay_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/search_screen.dart';
import '../screens/payment_methods_screen.dart';
import '../screens/receipt_info_edit_screen.dart';
import '../screens/resource_explorer_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/success_screen.dart';
import '../models/product.dart';
import '../state/auth_service.dart';
import '../widgets/hardware_scan_listener.dart';
import '../widgets/simulator_overlay.dart';

/// Lets code outside the routed page tree (KioskIdleGuard, mounted once
/// above MaterialApp — see main.dart) push/pop navigation and know which
/// route is on top, without needing a per-route BuildContext of its own.
/// Passing this key's own currentContext to Navigator.of()/showDialog()/
/// showModalBottomSheet() works because Navigator.of() special-cases a
/// context that IS a NavigatorState's own element.
final navigatorKey = GlobalKey<NavigatorState>();

/// Tracks the currently-top route's name for KioskIdleGuard, which needs to
/// know this without being built inside any specific route (it wraps
/// MaterialApp itself, not a page). Register once via MaterialApp's
/// navigatorObservers — see main.dart.
class KioskRouteObserver extends NavigatorObserver {
  static final ValueNotifier<String?> currentRouteName = ValueNotifier(null);

  void _update(Route<dynamic>? route) {
    final name = route?.settings.name;
    // A small notice dialog on top of a page does not change which page the
    // customer is on, so the idle timer must keep running underneath it —
    // otherwise a "Not found" dialog left on screen would stop it for good.
    if (name != null && Routes.transientOverlays.contains(name)) return;
    currentRouteName.value = name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(previousRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _update(newRoute);
}

/// Returns to Landing without rebuilding it.
///
/// Landing is the root route and hosts a WebView. Replacing it with
/// pushNamedAndRemoveUntil(landing, (_) => false) destroys the live WebView and
/// builds a new one, which shows a blank screen until the page paints again
/// on every idle reset / new order — and creating and destroying WebViews
/// repeatedly is costly on the kiosk's old Android WebView. Popping down to
/// the root keeps the already-painted Landing alive instead. Falls back to
/// the rebuild only if the root is somehow not Landing (e.g. a login flow
/// that replaced it).
void goHomeKeepingLanding(NavigatorState nav) {
  String? rootName;
  nav.popUntil((route) {
    if (route.isFirst) rootName = route.settings.name;
    return route.isFirst;
  });
  if (rootName != Routes.landing) {
    nav.pushNamedAndRemoveUntil(Routes.landing, (route) => false);
  }
}

class Routes {
  /// Name given to the one-at-a-time scan error / blocked-scan dialog (see
  /// utils/scan_actions.dart). It is listed in [transientOverlays].
  static const scanError = '/scan-error';

  /// Routes that are only notices on top of a page: KioskRouteObserver
  /// ignores them, so the page underneath stays "the current route".
  static const transientOverlays = <String>{scanError};

  static const landing = '/';
  static const scan = '/scan';
  static const cart = '/cart';
  static const checkout = '/checkout';
  static const pay = '/pay';
  static const success = '/success';
  static const settings = '/settings';
  static const browse = '/browse';
  static const productDetail = '/browse/product';
  static const kioskLogin = '/kiosk-login';
  static const invoice = '/invoice';
  static const search = '/search';
  static const categories = '/categories';
  static const resourceExplorer = '/admin/resources';
  static const receiptInfoEdit = '/admin/receipt-info/edit';
  static const paymentMethods = '/admin/payment-methods';

  static const odooAdmin = '/admin/odoo';
  static const landingEditor = '/admin/landing-editor';
  static const accounts = '/admin/accounts';
  static const accountEdit = '/admin/accounts/edit';

  /// Screens reachable while navigation is restricted — "customer already
  /// has the item in hand" is what's restricted, on a locked terminal.
  /// Account and admin screens are deliberately excluded: restricted
  /// navigation shouldn't offer a way to reach account/config screens
  /// mid-session.
  // browse/categories/search/productDetail are intentionally included so that
  // HTML landing-page banners (href="/screen?name=browse_screen&tag=X") can
  // navigate to catalog screens without being blocked
  // by the nav guard. Profile and admin/auth routes remain locked. Settings
  // is reachable only via the deliberate 10-tap + device-PIN gesture on the
  // Cart screen — nothing else links to it from kiosk mode, so adding it
  // here doesn't open any other door.
  static const kioskAllowlist = {landing, scan, cart, checkout, invoice, pay, success,
      browse, categories, search, productDetail, settings};

  /// Reused (see onGenerateRoute) to decide where the ambient hardware-
  /// scanner listener mounts: the same product/cart screens are exactly
  /// where a barcode scan should always be accepted. Deliberately NOT the
  /// same set as
  /// kioskAllowlist above — settings has no business accepting a barcode
  /// scan into the cart in the background.
  static const scanEnabledRoutes = {landing, scan, cart, checkout, invoice, pay, success,
      browse, categories, search, productDetail};

  /// Which non-Landing routes count as "after invoice" for idle-timer
  /// purposes (shorter, display-oriented countdown vs. the general
  /// before-invoice one). `invoice` is deliberately NOT here: an invoice
  /// that is still unpaid is a before-payment screen — the customer may be
  /// fetching a card or a phone — so it gets the longer before-invoice
  /// window. Once it is paid the guard suspends itself (see
  /// KioskIdleGuard._isPaid) and the paid dialog owns its own countdown.
  static const afterInvoiceRoutes = {success};
}

/// Route guard + idle-timer application.
///
/// Navigation lock — any route outside kioskAllowlist bounces back to
/// Landing, and every route is gated behind a device session (the device
/// login) first.
///
/// Every page is stacked with SimulatorOverlay *here*, inside the route's
/// own builder — deliberately not done once at the MaterialApp.builder
/// level (that was tried first and is wrong: MaterialApp.builder's `child`
/// wraps the Navigator, but the Overlay that Tooltip/Navigator.of() need
/// lives inside the Navigator, not above it — stacking the simulator as a
/// sibling of `child` put it outside that Overlay's reach entirely).
/// Building the Stack per-route instead means SimulatorOverlay is a true
/// descendant of the Navigator on every page, so it has real Overlay/
/// Navigator ancestors to find.
Route<dynamic> onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? Routes.landing;

  Widget page;
  // Kiosk is never anonymous: every route (including Landing itself) is
  // gated behind a device session. Checked before the allowlist below —
  // an unauthenticated device shouldn't even reach Landing's "start
  // scanning" entry point, let alone the routes that allowlist opens up.
  if (!authService.isDeviceSession && name != Routes.kioskLogin) {
    page = const KioskLoginScreen();
  } else if (!Routes.kioskAllowlist.contains(name)) {
    page = const LandingScreen();
  } else {
    switch (name) {
      case Routes.landing:
        page = const LandingScreen();
        break;
      case Routes.scan:
        page = const ScanScreen();
        break;
      case Routes.cart:
        page = const CartScreen();
        break;
      case Routes.checkout:
        page = const CheckoutScreen();
        break;
      case Routes.invoice:
        final orderId = settings.arguments as String?;
        page = orderId != null
            ? InvoiceScreen(orderId: orderId)
            : const LandingScreen();
        break;
      case Routes.pay:
        page = const PayScreen();
        break;
      case Routes.success:
        page = const SuccessScreen();
        break;
      case Routes.odooAdmin:
        page = const OdooAdminScreen();
        break;
      case Routes.landingEditor:
        page = const LandingEditorScreen();
        break;
      case Routes.resourceExplorer:
        page = const ResourceExplorerScreen();
        break;
      case Routes.accounts:
        page = const AccountsScreen();
        break;
      case Routes.accountEdit:
        final accountArg = settings.arguments;
        page = accountArg is AccountUser || accountArg == null
            ? AccountEditScreen(account: accountArg is AccountUser ? accountArg : null)
            : const LandingScreen();
        break;
      case Routes.paymentMethods:
        page = const PaymentMethodsScreen();
        break;
      case Routes.receiptInfoEdit:
        page = const ReceiptInfoEditScreen();
        break;
      case Routes.settings:
        page = const SettingsScreen();
        break;
      case Routes.browse:
        final browseArgs = settings.arguments;
        final categoryId = browseArgs is Map ? browseArgs['categoryId'] as int? : null;
        final browseTitle = browseArgs is Map ? browseArgs['title'] as String? : null;
        final searchQuery = browseArgs is Map ? browseArgs['searchQuery'] as String? : null;
        page = BrowseScreen(categoryId: categoryId, browseTitle: browseTitle, searchQuery: searchQuery);
        break;
      case Routes.kioskLogin:
        page = const KioskLoginScreen();
        break;
      case Routes.search:
        page = const SearchScreen();
        break;
      case Routes.categories:
        page = const CategoriesScreen();
        break;
      case Routes.productDetail:
        final product = settings.arguments;
        page = product is Product
            ? ProductDetailScreen(product: product)
            : const LandingScreen(); // no product passed — bad nav, bail safely
        break;
      default:
        page = const LandingScreen();
    }
  }

  // No per-route idle-timer wrapping anymore — KioskIdleGuard is mounted
  // ONCE, above MaterialApp (see main.dart), and tracks the current route
  // via KioskRouteObserver above instead of being rebuilt on every push.
  // The old design wrapped each guarded page in its own KioskIdleGuard
  // instance here; Flutter's normal push navigation never disposes routes
  // underneath a new one, so any two guarded routes stacked together (not
  // just cart+invoice — e.g. cart pushed to checkout without replacing)
  // ran two fully independent timers at once. Confirmed via trace logging
  // as the actual cause of a real black-screen crash: both fired within
  // milliseconds of each other, each showed its own warning sheet and
  // tried to redirect/reset Navigator state at the same time. A single
  // controller for the whole app makes that structurally impossible —
  // there is exactly one Timer and one "warning showing" flag in the
  // entire app, however many guarded routes are stacked underneath.
  //
  // Routes.invoice IS guarded (as a before-invoice screen): a customer who
  // creates an invoice and walks away, or backs out of a failed/cancelled
  // payment, must not be left on the unpaid invoice forever. The
  // auto-select/auto-pick logic in InvoiceScreen only covers the first few
  // seconds after the screen loads and never re-arms; this single guard
  // covers everything after that.

  return MaterialPageRoute(
    settings: settings,
    builder: (_) => Stack(
      children: [
        page,
        // Ambient hardware-scanner capture — mounted directly on whichever
        // product/cart screen is on top, not dependent on any TextField
        // holding focus, so it survives navigation away from Landing.
        if (Routes.scanEnabledRoutes.contains(name)) const HardwareScanListener(),
        const SimulatorOverlay(),
      ],
    ),
  );
}
