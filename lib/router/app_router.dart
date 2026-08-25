import 'package:flutter/material.dart';

import '../screens/browse_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/checkout_screen.dart';
import '../screens/debug_admin_stub_screen.dart';
import '../screens/odoo_admin_screen.dart';
import '../screens/invoice_screen.dart';
import '../screens/landing_screen.dart';
import '../screens/login_screen.dart';
import '../screens/orders_screen.dart';
import '../screens/pay_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/register_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/store_picker_screen.dart';
import '../screens/success_screen.dart';
import '../models/product.dart';
import '../state/browsing_mode_service.dart';
import '../widgets/kiosk_idle_guard.dart';
import '../widgets/mode_badge.dart';
import '../widgets/simulator_overlay.dart';

class Routes {
  static const landing = '/';
  static const scan = '/scan';
  static const cart = '/cart';
  static const checkout = '/checkout';
  static const pay = '/pay';
  static const success = '/success';
  static const settings = '/settings';
  static const profile = '/profile';
  static const browse = '/browse';
  static const productDetail = '/browse/product';
  static const register = '/register';
  static const login = '/login';
  static const storePicker = '/store-picker';
  static const invoice = '/invoice';
  static const orders = '/orders';
  static const search = '/search';
  static const categories = '/categories';

  /// Debug-only — deliberately NOT in kioskAllowlist. Exists to make the
  /// lock observable; see debug_admin_stub_screen.dart.
  static const debugAdminStub = '/debug/admin-stub';
  static const odooAdmin = '/admin/odoo';

  /// Screens reachable while navigation is restricted. Applies to BOTH
  /// Kiosk and Shopping — per the actual product model, "customer already
  /// has the item in hand" is what's restricted, and that's true for a
  /// locked terminal (Kiosk) and a customer's own phone (Shopping) alike.
  /// Only Normal mode gets the gate lifted. Settings, Profile, Browse,
  /// Product Detail, Register, Login, and Store Picker are all
  /// deliberately excluded either way — restricted navigation shouldn't
  /// offer a way to reach account/config screens mid-session. Browse is
  /// Normal-mode-only for now on purpose, even though MVP.txt's own table
  /// lists Shopping as having full browsing too — kept out of scope this
  /// round to avoid re-litigating Shopping's already-built fast-scan UX
  /// in the same change; see FRONTEND_AI.md.
  static const kioskAllowlist = {landing, scan, cart, checkout, invoice, pay, success};

  /// Which non-Landing routes represent "after invoice" for idle-timer
  /// purposes (shorter, display-oriented countdown vs. the general
  /// before-invoice one). Currently just Success — will include a QR
  /// screen once e-invoice/QR exists on the backend. Timers only ever
  /// apply in Kiosk mode — see onGenerateRoute.
  static const afterInvoiceRoutes = {invoice, success};
}

/// Route guard + idle-timer application.
///
/// Navigation lock applies to Kiosk AND Shopping — any route outside
/// kioskAllowlist bounces back to Landing in both. Only Normal gets full
/// navigation. Idle-recovery timers are narrower: Kiosk only, since
/// Shopping runs on the customer's own phone — there's no "walked away
/// from an unattended terminal" concern to guard against there, even
/// though its navigation is just as locked as Kiosk's.
///
/// Reads `browsingModeService.mode` directly rather than through Provider —
/// this function gets no BuildContext, so it can't watch a
/// ChangeNotifier; it just reads the current value fresh on every
/// navigation, which is what's needed here.
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
  final mode = browsingModeService.mode;
  final isRestrictedNav = mode == BrowsingMode.kiosk || mode == BrowsingMode.shopping;
  final isKiosk = mode == BrowsingMode.kiosk;

  Widget page;
  if (isRestrictedNav && !Routes.kioskAllowlist.contains(name)) {
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
      case Routes.debugAdminStub:
        page = const DebugAdminStubScreen();
        break;
      case Routes.odooAdmin:
        page = const OdooAdminScreen();
        break;
      case Routes.settings:
        page = const SettingsScreen();
        break;
      case Routes.profile:
        page = const ProfileScreen();
        break;
      case Routes.browse:
        final browseArgs = settings.arguments;
        final categoryId = browseArgs is Map ? browseArgs['categoryId'] as int? : null;
        final browseTitle = browseArgs is Map ? browseArgs['title'] as String? : null;
        page = BrowseScreen(categoryId: categoryId, browseTitle: browseTitle);
        break;
      case Routes.register:
        page = const RegisterScreen();
        break;
      case Routes.login:
        page = const LoginScreen();
        break;
      case Routes.storePicker:
        page = const StorePickerScreen();
        break;
      case Routes.orders:
        page = const OrdersScreen();
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

  // Only wrap kiosk-allowed non-landing pages — NOT pages that were
  // silently redirected to LandingScreen by the allowlist guard above.
  // Without the contains() check, a restricted route (e.g. /settings in
  // kiosk) would redirect to LandingScreen but still receive the idle
  // guard, causing the dialog to fire on the landing page itself.
  if (isKiosk && name != Routes.landing && Routes.kioskAllowlist.contains(name)) {
    page = KioskIdleGuard(
      afterInvoice: Routes.afterInvoiceRoutes.contains(name),
      child: page,
    );
  }

  return MaterialPageRoute(
    settings: settings,
    builder: (_) => Stack(
      children: [
        page,
        const SimulatorOverlay(),
        const ModeBadge(),
      ],
    ),
  );
}
