import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/pay_result.dart';
import '../models/quote.dart';
import '../models/product.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../services/scan_sound_service.dart';
import '../utils/locale_name.dart';
import 'auth_service.dart';
import 'locale_service.dart';
import 'store_config_service.dart';

const _uuid = Uuid();

/// Single source of truth for "where the customer is in the order", from
/// first scan through paid receipt. Mirrors FRONTEND_CONTEXT.md's flow
/// exactly: cart lives here client-side until checkout; orderId is minted
/// here (not by the backend); reset() is what both "New Order" and the
/// simulator's Home button call.
class OrderFlowController extends ChangeNotifier {
  final ApiClient _api;
  OrderFlowController(this._api);

  final List<CartItem> cart = [];
  Quote? quote;
  String? orderId;
  WahaOrder? order;
  PayResult? lastPayResult;

  bool busy = false;
  String? lastError;

  /// Effective storeId to send explicitly on quote/checkout, or null to
  /// let the backend resolve it from the session instead. Logged in with
  /// a store selected means omit it — session wins. Not logged in
  /// (anonymous Normal-mode browsing before checkout gates it, or a
  /// transient failure state) sends the device-configured
  /// StoreConfigService value explicitly. Scan/sync are NOT included in
  /// this — those always require storeId explicitly, no session
  /// fallback, per the backend doc.
  // null → let backend resolve from session (logged in + store selected)
  // storeConfigService.storeId → explicit (guest/anonymous, or no session store)
  // Both null → backend returns 400; that surfaces honestly as an error.
  int? get _sessionAwareStoreId =>
      (authService.isLoggedIn && authService.hasSelectedStore)
          ? null
          : storeConfigService.storeId; // null if no store configured yet

  /// Username is never sent explicitly anymore — every mode now resolves
  /// identity through AuthService (Kiosk via a provisioned login,
  /// Shopping via an auto-registered guest account, Normal via a real
  /// login gated at checkout). If checkout is somehow reached without a
  /// session, the backend's "username is required" 400 is the honest
  /// outcome — surfacing a real error beats sending a fabricated identity.
  String? get _sessionAwareUsername => null;

  String? get _authToken => authService.isLoggedIn ? authService.token : null;

  // ---- Scan ----------------------------------------------------------

  /// Returns the product on success. Throws ProductNotFoundException (404)
  /// or ProductNotSellableException (409) — the scan screen renders these
  /// as distinct states, not a generic toast, per FRONTEND_CONTEXT.md.
  ///
  /// Deliberately does NOT wait on the quote refresh before returning —
  /// that was the cause of the delayed "added to cart" toast (it was
  /// waiting on two sequential network calls, not one). The add itself is
  /// reflected immediately via notifyListeners(); price/quote catches up
  /// in the background and lands whenever it lands.
  Future<Product> scanBarcode(String barcode) async {
    final storeId = storeConfigService.storeId;
    if (storeId == null) throw StateError('No store configured');
    _setBusy(true);
    try {
      final product = await _api.getProductByBarcode(barcode, storeId);
      _addOrIncrement(product);
      notifyListeners();
      unawaited(_refreshQuote());
      return product;
    } on ProductNotFoundException {
      // Same chokepoint reasoning as the success sound in _addOrIncrement:
      // every caller (real scanner, simulator, camera scan) goes through
      // scanBarcode, so the failure sound belongs here, not per-caller.
      ScanSoundService.playFailure();
      rethrow;
    } on ProductNotSellableException {
      ScanSoundService.playFailure();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Single chokepoint for every "item entered the cart" path — scan,
  /// manual add from Browse/Search/Product Detail, and the simulator's
  /// fake scan. The success sound fires here, not per-caller, so it never
  /// has to be re-wired when a new add-to-cart entry point shows up.
  void _addOrIncrement(Product product) {
    final existing = cart.where((c) => c.productId == product.id);
    if (existing.isNotEmpty) {
      existing.first.quantity += 1;
    } else {
      final name = localeName(product.name, localeService.locale.languageCode);
      cart.add(CartItem(productId: product.id, name: name, quantity: 1,
          imageResourceId: product.imageResourceId));
    }
    ScanSoundService.playSuccess();
  }

  /// Adds a product straight to the cart — used by Browse/Product Detail,
  /// which already has the full Product object from the catalog fetch and
  /// doesn't need scanBarcode's redundant network round-trip. Same
  /// immediate-add-then-background-quote shape as scanBarcode, for the
  /// same reason (don't block the "added" feedback on a second call).
  void addProduct(Product product) {
    _addOrIncrement(product);
    notifyListeners();
    unawaited(_refreshQuote());
  }

  // ---- Cart ------------------------------------------------------------

  Future<void> updateQuantity(int productId, int quantity) async {
    if (quantity <= 0) {
      cart.removeWhere((c) => c.productId == productId);
    } else {
      final item = cart.firstWhere((c) => c.productId == productId);
      if (quantity > item.quantity) ScanSoundService.playSuccess();
      item.quantity = quantity;
    }
    await _refreshQuote();
  }

  Future<void> removeItem(int productId) async {
    cart.removeWhere((c) => c.productId == productId);
    await _refreshQuote();
  }

  /// Re-quotes against current cart. On a 409 (an item went unsellable
  /// between scan and now), the item is left in the cart and the error is
  /// surfaced — the cart screen decides how to prompt removal, this
  /// controller doesn't silently drop it. That's a UX call worth
  /// confirming with product, not something to bury in state logic.
  Future<void> _refreshQuote() async {
    if (cart.isEmpty) {
      quote = null;
      notifyListeners();
      return;
    }
    _setBusy(true);
    try {
      quote = await _api.quote(cart, storeId: _sessionAwareStoreId, token: _authToken);
      lastError = null;
    } on ApiException catch (e) {
      lastError = e.message;
    } catch (e) {
      // Broad on purpose: this can now run un-awaited (see scanBarcode),
      // so there's no caller left to catch a NetworkException or anything
      // else — surface it via lastError instead of letting it become an
      // unhandled Future error.
      lastError = 'Could not refresh price';
    } finally {
      _setBusy(false);
    }
  }

  // ---- Checkout ----------------------------------------------------

  /// Mints a UUID v7 the first time this is called for the current cart —
  /// v7, not v4: FRONTEND_CONTEXT.md is explicit orders.id is the DB's
  /// actual clustering key now, and v4's randomness fragments that index,
  /// while v7's embedded timestamp keeps inserts roughly time-ordered.
  /// NOTE: verify `.v7()` against the actually-installed `uuid` package
  /// version once `pub get` runs — the backend doc itself flags this API
  /// as one that "shifts" between package versions, and this couldn't be
  /// compiled/verified in this sandbox (no Flutter SDK — see SETUP.md).
  /// Reuses the same id on retry so a flaky-network retry is a safe no-op
  /// on the backend, per FRONTEND_CONTEXT.md's idempotent-create guarantee.
  ///
  /// Clears the cart on success — the invoice/order now holds the item
  /// list, the cart's job is done. Left untouched on failure so a 409
  /// (item went unsellable between quote and checkout) can be resolved
  /// and retried with the same items.
  Future<WahaOrder> checkout() async {
    // Reset if there's ANY existing order — idempotent retry only applies
    // when createOrder itself failed (threw) and order is still null.
    // An existing CREATED/PAID/FAILED order means this is a new checkout
    // and must get a fresh UUID, not reuse the old one.
    if (order != null) {
      orderId = null;
      order = null;
    }
    orderId ??= _uuid.v7();
    _setBusy(true);
    try {
      order = await _api.createOrder(
        orderId!,
        cart,
        storeId: _sessionAwareStoreId,
        username: _sessionAwareUsername,
        token: _authToken,
      );
      cart.clear();
      quote = null;
      lastError = null;
      return order!;
    } on ApiException catch (e) {
      lastError = e.message;
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  // ---- Pay ------------------------------------------------------------

  /// A decline (paid:false) is a normal return value, not a thrown error —
  /// callers check `.paid`, they don't wrap this in try/catch for that case.
  Future<PayResult> pay({String? simulateOutcome}) async {
    if (orderId == null) {
      throw StateError('pay() called before checkout()');
    }
    _setBusy(true);
    try {
      lastPayResult = await _api.pay(orderId!, simulateOutcome: simulateOutcome);
      order = lastPayResult!.order;
      lastError = null;
      return lastPayResult!;
    } on ApiException catch (e) {
      lastError = e.message;
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<WahaOrder> refreshOrder() async {
    if (orderId == null) {
      throw StateError('refreshOrder() called before checkout()');
    }
    order = await _api.getOrder(orderId!);
    notifyListeners();
    return order!;
  }

  /// Starts a Stripe/MyFatoorah session. For REDIRECT provider, returns a URL
  /// to open in the browser. For QR_LINK provider, also returns qrCodeDataUri
  /// and expiresAt for the kiosk QR screen.
  Future<PaymentSessionResult> createPaymentSession(
      {required String provider, required String providerMode}) async {
    if (orderId == null) {
      throw StateError('createPaymentSession() called before checkout()');
    }
    return _api.createPaymentSession(orderId!,
        provider: provider, providerMode: providerMode);
  }

  // ---- Reset ------------------------------------------------------------

  /// Used by "New Order" on the success screen, and by the simulator's Home
  /// button. Blows away everything unconditionally — appropriate for a dev
  /// shortcut, but note a real customer-facing "start over" mid-flow would
  /// need to actually account for an abandoned cart, not just discard it
  /// silently the way this does.
  void reset() {
    cart.clear();
    quote = null;
    orderId = null;
    order = null;
    lastPayResult = null;
    lastError = null;
    notifyListeners();
  }

  /// Clears just the cart/quote — distinct from reset(). Used by "Clear
  /// All" on the camera scan screen, before any order has been placed
  /// (orderId/order intentionally left alone; if an order somehow already
  /// exists this isn't the right call — reset() is).
  void clearCart() {
    cart.clear();
    quote = null;
    lastError = null;
    notifyListeners();
  }

  void _setBusy(bool value) {
    busy = value;
    notifyListeners();
  }
}
