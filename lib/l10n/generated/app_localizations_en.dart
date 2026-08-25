// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Waha';

  @override
  String get navHome => 'Home';

  @override
  String get navScan => 'Scan';

  @override
  String get navCart => 'Cart';

  @override
  String get navProfile => 'Profile';

  @override
  String get navSettings => 'Settings';

  @override
  String get navStores => 'Stores';

  @override
  String get landingHeadline => 'Scan your products to begin';

  @override
  String get landingSubtitle =>
      'No account, no waiting — pick items off the shelf and scan.';

  @override
  String get ctaStartScanning => 'Start Scanning';

  @override
  String get ctaContinueShopping => 'Continue Shopping';

  @override
  String get cartTitle => 'Cart';

  @override
  String get cartEmptyTitle => 'Cart is empty';

  @override
  String get cartEmptySubtitle => 'Scan a product to add it here.';

  @override
  String get cartSubtotal => 'Subtotal';

  @override
  String get cartTax => 'Tax';

  @override
  String get cartTotal => 'Total';

  @override
  String get checkoutButton => 'Checkout';

  @override
  String get payButton => 'Pay';

  @override
  String get payRetry => 'Retry Payment';

  @override
  String get paymentDeclined => 'Payment declined';

  @override
  String get payNoMethods => 'No payment methods available';

  @override
  String get payNoMethodsSubtitle =>
      'Please contact support or try again later.';

  @override
  String get payAlreadyPaid => 'Order Already Paid';

  @override
  String get successPaid => 'Paid';

  @override
  String get successNewOrder => 'New Order';

  @override
  String get successInvoiceQrLabel => 'Scan to view your e-invoice';

  @override
  String get receiptTitle => 'Receipt';

  @override
  String get settingsAppMode => 'App mode';

  @override
  String get modeNormal => 'Normal';

  @override
  String get modeKiosk => 'Kiosk';

  @override
  String get modeShopping => 'Shopping';

  @override
  String get settingsKioskTimers => 'Kiosk idle-recovery timers';

  @override
  String get settingsSaveTimers => 'Save Timers';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get profileTitle => 'Profile';

  @override
  String get navBrowse => 'Browse';

  @override
  String get browseTitle => 'Products';

  @override
  String get browseEmpty => 'No products found for this store.';

  @override
  String get browseLoadError => 'Couldn\'t load products.';

  @override
  String get browseRetry => 'Retry';

  @override
  String get browseLoadMore => 'Load More';

  @override
  String get productDetailAddToCart => 'Add to Cart';

  @override
  String get productDetailUnavailable => 'Not currently available';

  @override
  String get authUsername => 'Username';

  @override
  String get authPassword => 'Password';

  @override
  String get authRegisterTitle => 'Register';

  @override
  String get authLoginTitle => 'Log In';

  @override
  String get authRegisterCta => 'Create Account';

  @override
  String get authLoginCta => 'Log In';

  @override
  String get authSwitchToLogin => 'Already have an account? Log in';

  @override
  String get authSwitchToRegister => 'New here? Create an account';

  @override
  String get authRequiredError => 'Username and password are required';

  @override
  String get authPhoneLabel => 'Phone Number';

  @override
  String get authSendOtp => 'Send OTP';

  @override
  String get authAdminLogin => 'Admin Login';

  @override
  String get storePickerTitle => 'Choose a Store';

  @override
  String get storePickerEmpty => 'No stores available';

  @override
  String get storePickerSetDefault => 'Set as Default Store';

  @override
  String get storePickerDefaultSetSuffix => 'set as default store';

  @override
  String get storePickerGoToStore => 'Go to Store';

  @override
  String get storePickerMakeDefault => 'Make Default';

  @override
  String get storePickerIsDefault => 'Default';

  @override
  String get storePickerCurrentStore => 'Current';

  @override
  String get storePickerRefreshStore => 'Refresh Store';

  @override
  String get storePickerRefreshed => 'Store refreshed';

  @override
  String get profileLoggedInPrefix => 'Logged in as';

  @override
  String get profileGuestMessage =>
      'Not logged in — guest checkout still works.';

  @override
  String get profileLogout => 'Log Out';

  @override
  String get profileLogin => 'Log In';

  @override
  String get profileRegister => 'Register';

  @override
  String get profileChangeStore => 'Change Store';

  @override
  String get profileNoStoreSelected => 'No store selected';

  @override
  String get navOrders => 'Orders';

  @override
  String get navSearch => 'Search';

  @override
  String get navCategories => 'Categories';

  @override
  String get ordersTitle => 'My Orders';

  @override
  String get ordersEmpty => 'No orders yet.';

  @override
  String get ordersLoginPrompt => 'Log in to view your order history.';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Search products…';

  @override
  String get searchComingSoon => 'Search is coming soon.';

  @override
  String get categoriesTitle => 'Categories';

  @override
  String get categoriesComingSoon => 'Categories are coming soon.';

  @override
  String get viewCart => 'View Cart';

  @override
  String get homeSearchHint => 'What are you looking for?';

  @override
  String get homeProducts => 'Products';

  @override
  String get checkoutCreating => 'Creating your order…';

  @override
  String get checkoutSelectPayment => 'Select Payment Method';

  @override
  String get checkoutOrderSummary => 'Order Summary';

  @override
  String get seeAll => 'See all';

  @override
  String get recentlyAdded => 'Recently Added';

  @override
  String get invoiceTitle => 'Invoice';

  @override
  String get invoicePaid => 'PAID';

  @override
  String get invoiceUnpaid => 'Unpaid';

  @override
  String get invoicePending => 'Pending';

  @override
  String get invoiceCancelled => 'Cancelled';

  @override
  String invoicePaidVia(String method) {
    return 'Paid via $method';
  }

  @override
  String get invoiceSelectPayment => 'Select Payment Method';

  @override
  String get invoiceDownloadPdf => 'Download Invoice';

  @override
  String get invoiceDetails => 'Invoice Details';

  @override
  String get invoiceItems => 'Items';

  @override
  String get invoiceRef => 'Reference';

  @override
  String get invoiceDate => 'Date';

  @override
  String get invoiceStatusLabel => 'Status';

  @override
  String get invoiceOrderNum => 'Order';

  @override
  String get invoiceNewOrder => 'New Order';

  @override
  String get invoiceQrHint => 'Scan to open invoice on your phone';

  @override
  String get invoiceClosingSoon => 'Screen closing in';

  @override
  String get payConfirm => 'Confirm Payment';

  @override
  String get payProcessing => 'Processing payment…';

  @override
  String get payWaiting => 'Waiting for payment confirmation…';

  @override
  String get payCheckNow => 'I\'ve paid — Check Now';

  @override
  String get payOpenedBrowser =>
      'Complete payment in the browser tab that just opened.';

  @override
  String get language => 'Language';

  @override
  String get shareInvoice => 'Share Invoice';

  @override
  String get shareCopyLink => 'Copy Link';

  @override
  String get shareLinkCopied => 'Link copied to clipboard';

  @override
  String get cartClearTitle => 'Clear cart?';

  @override
  String get cartClearMessage => 'Remove all items from the cart.';

  @override
  String get cartClearConfirm => 'Clear';

  @override
  String get cartClearCancel => 'Cancel';

  @override
  String get perUnit => 'per unit';

  @override
  String get kioskIdleTitle => 'Are you still there?';

  @override
  String kioskIdleBeforeBody(int seconds) {
    return 'Your session will reset in $seconds seconds.';
  }

  @override
  String kioskIdleAfterBody(int seconds) {
    return 'This screen will close in $seconds seconds.';
  }

  @override
  String get kioskIdleContinue => 'Continue';

  @override
  String get kioskIdleNewOrder => 'Start New Order';

  @override
  String get kioskPaidTitle => 'Payment Received';

  @override
  String get kioskPaidScanHint => 'Scan to open your e-invoice';

  @override
  String kioskPaidClosingIn(int seconds) {
    return 'Screen closes in $seconds s';
  }

  @override
  String get kioskPaidResetTimer => 'Give me more time';

  @override
  String get kioskPaidNewOrder => 'New Order';
}
