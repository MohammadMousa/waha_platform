import 'package:flutter/material.dart';

import '../models/account_user.dart';
import '../models/store.dart';
import '../screens/browse_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/checkout_screen.dart';
import '../screens/debug_admin_stub_screen.dart';
import '../screens/account_edit_screen.dart';
import '../screens/accounts_screen.dart';
import '../screens/landing_editor_screen.dart';
import '../screens/odoo_admin_screen.dart';
import '../screens/invoice_screen.dart';
import '../screens/kiosk_login_screen.dart';
import '../screens/landing_screen.dart';
import '../screens/login_screen.dart';
import '../screens/orders_screen.dart';
import '../screens/pay_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/register_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/search_screen.dart';
import '../screens/category_edit_screen.dart';
import '../screens/product_edit_screen.dart';
import '../screens/payment_methods_screen.dart';
import '../screens/receipt_info_edit_screen.dart';
import '../screens/resource_explorer_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/store_edit_screen.dart';
import '../screens/store_picker_screen.dart';
import '../screens/success_screen.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../widgets/hardware_scan_listener.dart';
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
  static const kioskLogin = '/kiosk-login';
  static const storePicker = '/store-picker';
  static const invoice = '/invoice';
  static const orders = '/orders';
  static const search = '/search';
  static const categories = '/categories';
  static const resourceExplorer = '/admin/resources';
  static const productEdit = '/admin/product/edit';
  static const categoryEdit = '/admin/category/edit';
  static const storeEdit = '/admin/store/edit';
  static const receiptInfoEdit = '/admin/receipt-info/edit';
  static const paymentMethods = '/admin/payment-methods';

  /// Debug-only — deliberately NOT in kioskAllowlist. Exists to make the
  /// lock observable; see debug_admin_stub_screen.dart.
  static const debugAdminStub = '/debug/admin-stub';
  static const odooAdmin = '/admin/odoo';
  static const landingEditor = '/admin/landing-editor';
  static const accounts = '/admin/accounts';
  static const accountEdit = '/admin/accounts/edit';

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
  // browse/categories/search/productDetail are intentionally included so that
  // HTML landing-page banners (href="/screen?name=browse_screen&tag=X") can
  // navigate to catalog screens from kiosk/shopping mode without being blocked
  // by the nav guard. Profile and admin/auth routes remain locked. Settings
  // is reachable only via the deliberate 10-tap + device-PIN gesture on the
  // Cart screen — nothing else links to it from kiosk mode, so adding it
  // here doesn't open any other door.
  static const kioskAllowlist = {landing, scan, cart, checkout, invoice, pay, success,
      browse, categories, search, productDetail, settings};

  /// Reused (see onGenerateRoute) to decide where the ambient hardware-
  /// scanner listener mounts: the same product/cart screens are exactly
  /// where a barcode scan should always be accepted, in every mode — not
  /// just Kiosk/Shopping's restricted set. Deliberately NOT the same set as
  /// kioskAllowlist above — settings has no business accepting a barcode
  /// scan into the cart in the background.
  static const scanEnabledRoutes = {landing, scan, cart, checkout, invoice, pay, success,
      browse, categories, search, productDetail};

  /// Which non-Landing routes represent "after invoice" for idle-timer
  /// purposes (shorter, display-oriented countdown vs. the general
  /// before-invoice one). `invoice` itself is excluded from receiving any
  /// guard at all now (see onGenerateRoute) — it's listed here only so a
  /// direct check against this set still classifies it correctly if that
  /// ever changes back. `success` is still guarded — worth knowing that
  /// it has the exact same "cart's guard is still alive underneath"
  /// exposure `invoice` had (see onGenerateRoute's comment on why invoice
  /// was excluded); success just doesn't have an auto-select-style escape
  /// hatch of its own the way invoice now does, so it hasn't been touched.
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
  // Kiosk is never anonymous: every route (including Landing itself) is
  // gated behind a device session. Checked before the allowlist below —
  // an unauthenticated device shouldn't even reach Landing's "start
  // scanning" entry point, let alone the routes that allowlist opens up.
  if (isKiosk && !authService.isDeviceSession && name != Routes.kioskLogin) {
    page = const KioskLoginScreen();
  } else if (isRestrictedNav && !Routes.kioskAllowlist.contains(name)) {
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
      case Routes.landingEditor:
        page = const LandingEditorScreen();
        break;
      case Routes.resourceExplorer:
        page = const ResourceExplorerScreen();
        break;
      case Routes.productEdit:
        final productId = settings.arguments;
        page = productId is int
            ? ProductEditScreen(productId: productId)
            : const LandingScreen();
        break;
      case Routes.categoryEdit:
        final catArg = settings.arguments;
        page = catArg is Category
            ? CategoryEditScreen(category: catArg)
            : const LandingScreen();
        break;
      case Routes.storeEdit:
        final storeArg = settings.arguments;
        // null argument = create mode; Store argument = edit mode
        page = (storeArg is Store || storeArg == null)
            ? StoreEditScreen(store: storeArg is Store ? storeArg : null)
            : const LandingScreen();
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
      case Routes.profile:
        page = const ProfileScreen();
        break;
      case Routes.browse:
        final browseArgs = settings.arguments;
        final categoryId = browseArgs is Map ? browseArgs['categoryId'] as int? : null;
        final browseTitle = browseArgs is Map ? browseArgs['title'] as String? : null;
        final searchQuery = browseArgs is Map ? browseArgs['searchQuery'] as String? : null;
        page = BrowseScreen(categoryId: categoryId, browseTitle: browseTitle, searchQuery: searchQuery);
        break;
      case Routes.register:
        page = const RegisterScreen();
        break;
      case Routes.login:
        page = const LoginScreen();
        break;
      case Routes.kioskLogin:
        page = const KioskLoginScreen();
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
  //
  // Routes.invoice is deliberately excluded — it's reached via a push
  // chain from cart (cart's own push is never replaced), so cart's guard
  // stays alive underneath the whole time regardless. Wrapping invoice
  // too meant TWO independent guards could fire within milliseconds of
  // each other, each trying to redirect/reset at once — confirmed via
  // trace logging as the actual cause of an intermittent black screen
  // (see InvoiceScreen's own auto-select-or-auto-pick logic, which now
  // replaces the need for an idle guard there entirely: it always
  // resolves on its own within a few seconds, guard or not).
  if (isKiosk &&
      name != Routes.landing &&
      name != Routes.invoice &&
      Routes.kioskAllowlist.contains(name)) {
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
        // Ambient hardware-scanner capture — mounted directly on whichever
        // product/cart screen is on top, not dependent on any TextField
        // holding focus, so it survives navigation away from Landing.
        if (Routes.scanEnabledRoutes.contains(name)) const HardwareScanListener(),
        const SimulatorOverlay(),
        const ModeBadge(),
      ],
    ),
  );
}
