import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Waha'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get navScan;

  /// No description provided for @navCart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get navCart;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navStores.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get navStores;

  /// No description provided for @landingHeadline.
  ///
  /// In en, this message translates to:
  /// **'Scan your products to begin'**
  String get landingHeadline;

  /// No description provided for @landingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No account, no waiting — pick items off the shelf and scan.'**
  String get landingSubtitle;

  /// No description provided for @ctaStartScanning.
  ///
  /// In en, this message translates to:
  /// **'Start Scanning'**
  String get ctaStartScanning;

  /// No description provided for @ctaContinueShopping.
  ///
  /// In en, this message translates to:
  /// **'Continue Shopping'**
  String get ctaContinueShopping;

  /// No description provided for @cartTitle.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get cartTitle;

  /// No description provided for @cartEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Cart is empty'**
  String get cartEmptyTitle;

  /// No description provided for @cartEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a product to add it here.'**
  String get cartEmptySubtitle;

  /// No description provided for @cartSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get cartSubtotal;

  /// No description provided for @cartTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get cartTax;

  /// No description provided for @cartTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get cartTotal;

  /// No description provided for @checkoutButton.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkoutButton;

  /// No description provided for @payButton.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get payButton;

  /// No description provided for @payRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry Payment'**
  String get payRetry;

  /// No description provided for @paymentDeclined.
  ///
  /// In en, this message translates to:
  /// **'Payment declined'**
  String get paymentDeclined;

  /// No description provided for @payNoMethods.
  ///
  /// In en, this message translates to:
  /// **'No payment methods available'**
  String get payNoMethods;

  /// No description provided for @payNoMethodsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please contact support or try again later.'**
  String get payNoMethodsSubtitle;

  /// No description provided for @payAlreadyPaid.
  ///
  /// In en, this message translates to:
  /// **'Order Already Paid'**
  String get payAlreadyPaid;

  /// No description provided for @successPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get successPaid;

  /// No description provided for @successNewOrder.
  ///
  /// In en, this message translates to:
  /// **'New Order'**
  String get successNewOrder;

  /// No description provided for @successInvoiceQrLabel.
  ///
  /// In en, this message translates to:
  /// **'Scan to view your e-invoice'**
  String get successInvoiceQrLabel;

  /// No description provided for @receiptTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receiptTitle;

  /// No description provided for @settingsAppMode.
  ///
  /// In en, this message translates to:
  /// **'App mode'**
  String get settingsAppMode;

  /// No description provided for @modeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get modeNormal;

  /// No description provided for @modeKiosk.
  ///
  /// In en, this message translates to:
  /// **'Kiosk'**
  String get modeKiosk;

  /// No description provided for @modeShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get modeShopping;

  /// No description provided for @settingsKioskTimers.
  ///
  /// In en, this message translates to:
  /// **'Kiosk idle-recovery timers'**
  String get settingsKioskTimers;

  /// No description provided for @settingsSaveTimers.
  ///
  /// In en, this message translates to:
  /// **'Save Timers'**
  String get settingsSaveTimers;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @navBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get navBrowse;

  /// No description provided for @browseTitle.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get browseTitle;

  /// No description provided for @browseEmpty.
  ///
  /// In en, this message translates to:
  /// **'No products found for this store.'**
  String get browseEmpty;

  /// No description provided for @browseLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load products.'**
  String get browseLoadError;

  /// No description provided for @browseRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get browseRetry;

  /// No description provided for @browseLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load More'**
  String get browseLoadMore;

  /// No description provided for @productDetailAddToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to Cart'**
  String get productDetailAddToCart;

  /// No description provided for @productDetailUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not currently available'**
  String get productDetailUnavailable;

  /// No description provided for @authUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsername;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get authRegisterTitle;

  /// No description provided for @authLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get authLoginTitle;

  /// No description provided for @authRegisterCta.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get authRegisterCta;

  /// No description provided for @authLoginCta.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get authLoginCta;

  /// No description provided for @authSwitchToLogin.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Log in'**
  String get authSwitchToLogin;

  /// No description provided for @authSwitchToRegister.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get authSwitchToRegister;

  /// No description provided for @authRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Username and password are required'**
  String get authRequiredError;

  /// No description provided for @authPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get authPhoneLabel;

  /// No description provided for @authSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get authSendOtp;

  /// No description provided for @authAdminLogin.
  ///
  /// In en, this message translates to:
  /// **'Admin Login'**
  String get authAdminLogin;

  /// No description provided for @stores.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get stores;

  /// No description provided for @storePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a Store'**
  String get storePickerTitle;

  /// No description provided for @storePickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No stores available'**
  String get storePickerEmpty;

  /// No description provided for @storePickerSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as Default Store'**
  String get storePickerSetDefault;

  /// No description provided for @storePickerDefaultSetSuffix.
  ///
  /// In en, this message translates to:
  /// **'set as default store'**
  String get storePickerDefaultSetSuffix;

  /// No description provided for @storePickerGoToStore.
  ///
  /// In en, this message translates to:
  /// **'Go to Store'**
  String get storePickerGoToStore;

  /// No description provided for @storePickerMakeDefault.
  ///
  /// In en, this message translates to:
  /// **'Make Default'**
  String get storePickerMakeDefault;

  /// No description provided for @storePickerIsDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get storePickerIsDefault;

  /// No description provided for @storePickerCurrentStore.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get storePickerCurrentStore;

  /// No description provided for @storePickerRefreshStore.
  ///
  /// In en, this message translates to:
  /// **'Refresh Store'**
  String get storePickerRefreshStore;

  /// No description provided for @storePickerRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Store refreshed'**
  String get storePickerRefreshed;

  /// No description provided for @profileLoggedInPrefix.
  ///
  /// In en, this message translates to:
  /// **'Logged in as'**
  String get profileLoggedInPrefix;

  /// No description provided for @profileGuestMessage.
  ///
  /// In en, this message translates to:
  /// **'Not logged in — guest checkout still works.'**
  String get profileGuestMessage;

  /// No description provided for @profileLogout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get profileLogout;

  /// No description provided for @profileLogin.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get profileLogin;

  /// No description provided for @profileRegister.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get profileRegister;

  /// No description provided for @profileChangeStore.
  ///
  /// In en, this message translates to:
  /// **'Change Store'**
  String get profileChangeStore;

  /// No description provided for @profileNoStoreSelected.
  ///
  /// In en, this message translates to:
  /// **'No store selected'**
  String get profileNoStoreSelected;

  /// No description provided for @navOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get navOrders;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get navCategories;

  /// No description provided for @ordersTitle.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get ordersTitle;

  /// No description provided for @ordersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No orders yet.'**
  String get ordersEmpty;

  /// No description provided for @ordersLoginPrompt.
  ///
  /// In en, this message translates to:
  /// **'Log in to view your order history.'**
  String get ordersLoginPrompt;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search products…'**
  String get searchHint;

  /// No description provided for @searchComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Search is coming soon.'**
  String get searchComingSoon;

  /// No description provided for @categoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesTitle;

  /// No description provided for @categoriesComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Categories are coming soon.'**
  String get categoriesComingSoon;

  /// No description provided for @viewCart.
  ///
  /// In en, this message translates to:
  /// **'View Cart'**
  String get viewCart;

  /// No description provided for @homeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'What are you looking for?'**
  String get homeSearchHint;

  /// No description provided for @homeProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get homeProducts;

  /// No description provided for @checkoutCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating your order…'**
  String get checkoutCreating;

  /// No description provided for @checkoutSelectPayment.
  ///
  /// In en, this message translates to:
  /// **'Select Payment Method'**
  String get checkoutSelectPayment;

  /// No description provided for @checkoutOrderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order Summary'**
  String get checkoutOrderSummary;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @recentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently Added'**
  String get recentlyAdded;

  /// No description provided for @invoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoiceTitle;

  /// No description provided for @invoicePaid.
  ///
  /// In en, this message translates to:
  /// **'PAID'**
  String get invoicePaid;

  /// No description provided for @invoiceUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get invoiceUnpaid;

  /// No description provided for @invoicePending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get invoicePending;

  /// No description provided for @invoiceCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get invoiceCancelled;

  /// No description provided for @invoicePaidVia.
  ///
  /// In en, this message translates to:
  /// **'Paid via {method}'**
  String invoicePaidVia(String method);

  /// No description provided for @invoiceSelectPayment.
  ///
  /// In en, this message translates to:
  /// **'Select Payment Method'**
  String get invoiceSelectPayment;

  /// No description provided for @invoiceDownloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download Invoice'**
  String get invoiceDownloadPdf;

  /// No description provided for @invoiceDetails.
  ///
  /// In en, this message translates to:
  /// **'Invoice Details'**
  String get invoiceDetails;

  /// No description provided for @invoiceItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get invoiceItems;

  /// No description provided for @invoiceRef.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get invoiceRef;

  /// No description provided for @invoiceDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get invoiceDate;

  /// No description provided for @invoiceStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get invoiceStatusLabel;

  /// No description provided for @invoiceOrderNum.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get invoiceOrderNum;

  /// No description provided for @invoiceNewOrder.
  ///
  /// In en, this message translates to:
  /// **'New Order'**
  String get invoiceNewOrder;

  /// No description provided for @invoiceQrHint.
  ///
  /// In en, this message translates to:
  /// **'Scan to open invoice on your phone'**
  String get invoiceQrHint;

  /// No description provided for @invoiceClosingSoon.
  ///
  /// In en, this message translates to:
  /// **'Screen closing in'**
  String get invoiceClosingSoon;

  /// No description provided for @payConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm Payment'**
  String get payConfirm;

  /// No description provided for @payProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing payment…'**
  String get payProcessing;

  /// No description provided for @payWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment confirmation…'**
  String get payWaiting;

  /// No description provided for @payCheckNow.
  ///
  /// In en, this message translates to:
  /// **'I\'ve paid — Check Now'**
  String get payCheckNow;

  /// No description provided for @payOpenedBrowser.
  ///
  /// In en, this message translates to:
  /// **'Complete payment in the browser tab that just opened.'**
  String get payOpenedBrowser;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @shareInvoice.
  ///
  /// In en, this message translates to:
  /// **'Share Invoice'**
  String get shareInvoice;

  /// No description provided for @shareCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get shareCopyLink;

  /// No description provided for @shareLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get shareLinkCopied;

  /// No description provided for @cartClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear cart?'**
  String get cartClearTitle;

  /// No description provided for @cartClearMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove all items from the cart.'**
  String get cartClearMessage;

  /// No description provided for @cartClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get cartClearConfirm;

  /// No description provided for @cartClearCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cartClearCancel;

  /// No description provided for @perUnit.
  ///
  /// In en, this message translates to:
  /// **'per unit'**
  String get perUnit;

  /// No description provided for @kioskIdleTitle.
  ///
  /// In en, this message translates to:
  /// **'Are you still there?'**
  String get kioskIdleTitle;

  /// No description provided for @kioskIdleBeforeBody.
  ///
  /// In en, this message translates to:
  /// **'Your session will reset in {seconds} seconds.'**
  String kioskIdleBeforeBody(int seconds);

  /// No description provided for @kioskIdleAfterBody.
  ///
  /// In en, this message translates to:
  /// **'This screen will close in {seconds} seconds.'**
  String kioskIdleAfterBody(int seconds);

  /// No description provided for @kioskIdleContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get kioskIdleContinue;

  /// No description provided for @kioskIdleNewOrder.
  ///
  /// In en, this message translates to:
  /// **'Start New Order'**
  String get kioskIdleNewOrder;

  /// No description provided for @kioskPaidTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Received'**
  String get kioskPaidTitle;

  /// No description provided for @kioskPaidScanHint.
  ///
  /// In en, this message translates to:
  /// **'Scan to open your e-invoice'**
  String get kioskPaidScanHint;

  /// No description provided for @kioskPaidClosingIn.
  ///
  /// In en, this message translates to:
  /// **'Screen closes in {seconds} s'**
  String kioskPaidClosingIn(int seconds);

  /// No description provided for @kioskPaidResetTimer.
  ///
  /// In en, this message translates to:
  /// **'Give me more time'**
  String get kioskPaidResetTimer;

  /// No description provided for @kioskPaidNewOrder.
  ///
  /// In en, this message translates to:
  /// **'New Order'**
  String get kioskPaidNewOrder;

  /// No description provided for @invoiceDueLabel.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get invoiceDueLabel;

  /// No description provided for @adminPaymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Payment Methods'**
  String get adminPaymentMethods;

  /// No description provided for @adminPaymentMethodsHint.
  ///
  /// In en, this message translates to:
  /// **'Enable or disable payment methods for this store.'**
  String get adminPaymentMethodsHint;

  /// No description provided for @adminPaymentMethodsSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get adminPaymentMethodsSaving;

  /// No description provided for @mobilePaymentScanHint.
  ///
  /// In en, this message translates to:
  /// **'Scan to pay from your phone'**
  String get mobilePaymentScanHint;

  /// No description provided for @mobilePaymentPolling.
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment…'**
  String get mobilePaymentPolling;

  /// No description provided for @qrPayTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan to Pay'**
  String get qrPayTitle;

  /// No description provided for @qrPayInstruction.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code with your phone to complete payment.'**
  String get qrPayInstruction;

  /// No description provided for @qrPayWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment…'**
  String get qrPayWaiting;

  /// No description provided for @qrPayExpired.
  ///
  /// In en, this message translates to:
  /// **'Payment link expired'**
  String get qrPayExpired;

  /// No description provided for @qrPayExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'The QR code has expired. Please go back and try again.'**
  String get qrPayExpiredBody;

  /// No description provided for @qrPayConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed'**
  String get qrPayConfirmed;

  /// No description provided for @qrPayCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get qrPayCancel;

  /// No description provided for @qrPayGoBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get qrPayGoBack;

  /// No description provided for @qrPayCancelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel this payment and go back?'**
  String get qrPayCancelConfirm;

  /// No description provided for @qrPayCancelContinue.
  ///
  /// In en, this message translates to:
  /// **'Keep Waiting'**
  String get qrPayCancelContinue;

  /// No description provided for @qrPayExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {minutes}:{seconds}'**
  String qrPayExpiresIn(String minutes, String seconds);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
