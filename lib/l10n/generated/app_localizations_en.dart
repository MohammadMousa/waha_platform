// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get timeJustNow => 'just now';

  @override
  String timeAgo(String t) {
    return '$t ago';
  }

  @override
  String timeDays(String n) {
    return '${n}d';
  }

  @override
  String timeHours(String n) {
    return '${n}h';
  }

  @override
  String timeMinutes(String n) {
    return '${n}m';
  }

  @override
  String timeSeconds(String n) {
    return '${n}s';
  }

  @override
  String get timeAm => 'AM';

  @override
  String get timePm => 'PM';

  @override
  String offlineLastAttempt(String when) {
    return 'Last attempt: $when';
  }

  @override
  String offlineRemovals(String last, String total) {
    return 'Removals: $last in the last check, $total in total';
  }

  @override
  String offlineRemovalsChecked(String when) {
    return 'Last removals check: $when';
  }

  @override
  String get offlineRemovalsNever => 'Removals: not checked yet';

  @override
  String get offlineRemovalsUnsupported =>
      'Removals: not supported by the server';

  @override
  String ordersLastAttempt(String when) {
    return 'Last send attempt: $when';
  }

  @override
  String offlineLastPull(String when) {
    return 'Last successful pull: $when';
  }

  @override
  String ordersLastAccepted(String when) {
    return 'Last accepted by the server: $when';
  }

  @override
  String get appTitle => 'Waha';

  @override
  String get navHome => 'Home';

  @override
  String get navCart => 'Cart';

  @override
  String get navSettings => 'Settings';

  @override
  String get landingHeadline => 'Scan your products to begin';

  @override
  String get landingSubtitle =>
      'No account, no waiting — pick items off the shelf and scan.';

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
  String get cartDiscount => 'Discount';

  @override
  String get cartBeforeDiscount => 'Before Discount';

  @override
  String get cartZeroDueHint => 'Add more items to benefit from the offer';

  @override
  String get cartTotal => 'Total';

  @override
  String get checkoutButton => 'Buy & Pay';

  @override
  String get devicePinDialogTitle => 'Device Settings';

  @override
  String get devicePinSignedInAs => 'Signed in as';

  @override
  String get devicePinLabel => 'Enter device PIN';

  @override
  String get devicePinUnlock => 'Unlock';

  @override
  String get commonOk => 'OK';

  @override
  String get scanFailedTitle => 'Scan failed';

  @override
  String scanNotFoundMessage(String barcode) {
    return 'No product found for barcode $barcode';
  }

  @override
  String get scanNotSellableMessage =>
      'This product is not available for sale right now.';

  @override
  String get offlineNotReady =>
      'Products are still loading, please wait a moment.';

  @override
  String get couponErrNotFound => 'This coupon code is not valid.';

  @override
  String get couponErrDisabled => 'This coupon is not active.';

  @override
  String get couponErrNotYetValid => 'This coupon is not valid yet.';

  @override
  String get couponErrExpired => 'This coupon has expired.';

  @override
  String get couponErrWrongStore => 'This coupon is not valid in this store.';

  @override
  String get couponErrUsageLimit => 'This coupon has reached its usage limit.';

  @override
  String get couponErrUserLimit =>
      'You have reached the usage limit for this coupon.';

  @override
  String get couponErrAmountExhausted =>
      'The discount available with this coupon has been used up.';

  @override
  String get couponErrUserAmountExhausted =>
      'You have used up the discount available to you with this coupon.';

  @override
  String get couponErrMinimum =>
      'The cart total is below the minimum for this coupon.';

  @override
  String get couponErrNotCombinable =>
      'This coupon can\'t be combined with the current offers.';

  @override
  String get couponErrNotApplicable =>
      'No item in the cart qualifies for this coupon.';

  @override
  String get couponErrGeneric => 'The coupon could not be applied.';

  @override
  String couponApplied(String code) {
    return 'Coupon $code applied';
  }

  @override
  String couponRejected(String code, String reason) {
    return 'Coupon $code: $reason';
  }

  @override
  String couponDropped(String code, String reason) {
    return 'Coupon $code was removed: $reason';
  }

  @override
  String get couponStage => 'Coupons can\'t be added at this stage';

  @override
  String get couponNeedItems => 'Add some items to the cart first';

  @override
  String get couponCheckFailed =>
      'Can\'t reach the server, so the coupon can\'t be checked. Try again when connected.';

  @override
  String cartCoupon(String code) {
    return 'Coupon $code';
  }

  @override
  String get cartCouponRemove => 'Remove coupon';

  @override
  String get offlineDataTitle => 'Offline data';

  @override
  String offlineRows(String feed, String count) {
    return '$feed: $count rows';
  }

  @override
  String get offlineFullDone => '(full pull done)';

  @override
  String get offlineNotComplete => '(not complete)';

  @override
  String offlineCursor(String since, String afterId) {
    return 'cursor $since / $afterId';
  }

  @override
  String offlineErrorLine(String error) {
    return 'error: $error';
  }

  @override
  String get offlinePullNow => 'Pull now';

  @override
  String get offlinePulling => 'Pulling…';

  @override
  String offlineLastResult(String time, String message) {
    return 'Last result ($time): $message';
  }

  @override
  String pullDone(String count) {
    return 'Pull finished: $count rows updated';
  }

  @override
  String pullFailed(String error) {
    return 'Pull failed: $error';
  }

  @override
  String get pullNoSession => 'Pull skipped: this device is not signed in';

  @override
  String get pullCustomerActive =>
      'Pull skipped: the screen is in use. Try again when it is idle.';

  @override
  String get pullBusy => 'A pull is already running…';

  @override
  String pullServerBusy(String seconds) {
    return 'Pull stopped: the server asked to wait $seconds seconds';
  }

  @override
  String get pullAuthStopped =>
      'Pull stopped: the server refused this device\'s login';

  @override
  String ordersTitle(String pending, String dead) {
    return 'Orders to send ($pending waiting, $dead failed)';
  }

  @override
  String get ordersAuthStopped =>
      'Sending is stopped: the server refused this device\'s session.';

  @override
  String get ordersAuthStoppedHint =>
      'The orders are kept and will be sent once the device is signed in again.';

  @override
  String get ordersNoFailed => 'No failed orders.';

  @override
  String ordersTotal(String ref, String amount, String currency) {
    return '$ref   total $amount $currency';
  }

  @override
  String ordersMade(String at) {
    return 'made $at';
  }

  @override
  String get ordersRetry => 'Retry';

  @override
  String get ordersSendNow => 'Send now';

  @override
  String get ordersSending => 'Sending…';

  @override
  String sendDone(String count) {
    return 'Sent $count order(s) to the server';
  }

  @override
  String get sendNothing => 'Nothing is waiting to send';

  @override
  String sendPartial(String sent, String rejected) {
    return 'Sent $sent; the server rejected $rejected (see the failed list)';
  }

  @override
  String sendRejected(String rejected) {
    return 'The server rejected $rejected order(s) (see the failed list)';
  }

  @override
  String sendFailed(String error) {
    return 'Sending failed: $error';
  }

  @override
  String get sendNoSession => 'Sending skipped: this device is not signed in';

  @override
  String get sendAuthStopped =>
      'Sending stopped: the server refused this device\'s login';

  @override
  String get sendBusy => 'Already sending…';

  @override
  String scanFailedMessage(String error) {
    return 'Scan failed: $error';
  }

  @override
  String get scanBlockedUnpaidTitle => 'Order not paid yet';

  @override
  String get scanBlockedUnpaidMessage =>
      'You haven\'t paid for this order yet. Please complete payment first.';

  @override
  String get settingsShowCartMenuKiosk => 'Show cart menu in Kiosk mode';

  @override
  String get paymentDeclined => 'Payment declined';

  @override
  String get payNoMethods => 'No payment methods available';

  @override
  String get successPaid => 'Paid';

  @override
  String get successNewOrder => 'New Order';

  @override
  String get successInvoiceQrLabel => 'Scan to view your e-invoice';

  @override
  String get receiptTitle => 'Receipt';

  @override
  String get settingsKioskTimers => 'Kiosk idle-recovery timers';

  @override
  String get settingsSaveTimers => 'Save Timers';

  @override
  String get settingsLanguage => 'Language';

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
  String get authLoginCta => 'Log In';

  @override
  String get authRequiredError => 'Username and password are required';

  @override
  String get authDeviceLogin => 'Device Login';

  @override
  String get authPinCode => 'PIN';

  @override
  String get authDeviceLoginSubtitle =>
      'Sign in with this device\'s kiosk account';

  @override
  String get stores => 'Stores';

  @override
  String get profileLogout => 'Log Out';

  @override
  String get profileLogoutFailed =>
      'Couldn\'t sign out. Check the connection and try again.';

  @override
  String get profileLogin => 'Log In';

  @override
  String get profileNoStoreSelected => 'No store selected';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Search products…';

  @override
  String get categoriesTitle => 'Categories';

  @override
  String get viewCart => 'View Cart';

  @override
  String get checkoutCreating => 'Creating your order…';

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
  String get invoiceItems => 'Items';

  @override
  String get invoiceOrderNum => 'Order';

  @override
  String get invoiceNewOrder => 'New Order';

  @override
  String get payConfirm => 'Confirm Payment';

  @override
  String get payWaiting => 'Waiting for payment confirmation…';

  @override
  String get payCheckNow => 'I\'ve paid — Check Now';

  @override
  String get language => 'Language';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get perUnit => 'per unit';

  @override
  String get priceInclVat => 'incl. VAT';

  @override
  String get priceExclVat => 'excl. VAT';

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

  @override
  String get terminalTitle => 'Card Terminal';

  @override
  String get terminalConnecting => 'Connecting to terminal…';

  @override
  String get terminalNotConnected =>
      'Terminal not connected — check the USB cable.';

  @override
  String get terminalSwipeCard => 'Tap or swipe your card on the terminal';

  @override
  String terminalPreviousPaymentPending(int seconds) {
    return 'Getting the terminal ready. Please wait $seconds seconds…';
  }

  @override
  String get terminalNotReady =>
      'The card terminal is not ready. Please try again in a moment or ask staff for help.';

  @override
  String autoRestartMessage(int seconds) {
    return 'Restarting in $seconds s';
  }

  @override
  String get autoRestartNotNow => 'Not now';

  @override
  String get autoRestartNow => 'Restart now';

  @override
  String terminalBusyTryLater(int seconds) {
    return 'The card terminal is not ready. Please try again in $seconds seconds.';
  }

  @override
  String terminalSessionStartFailed(String error) {
    return 'Failed to start session: $error';
  }

  @override
  String terminalApprovedNotRecorded(String error) {
    return 'Approved on the terminal but could not be recorded ($error) — do not retry, contact support.';
  }

  @override
  String get terminalPaymentFailedTitle => 'Payment Failed';

  @override
  String get terminalResultUnknownTitle => 'Payment result unknown';

  @override
  String get terminalResultUnknown =>
      'The card terminal did not answer in time. Do not pay again yet — please ask staff to check the terminal first.';

  @override
  String get terminalClose => 'Close';

  @override
  String autoSelectingIn(int seconds) {
    return 'Auto-selecting in ${seconds}s — tap to pay now';
  }

  @override
  String get invoiceDueLabel => 'Due';

  @override
  String get mobilePaymentScanHint => 'Scan to pay from your phone';

  @override
  String get mobilePaymentPolling => 'Waiting for payment…';

  @override
  String get qrPayTitle => 'Scan to Pay';

  @override
  String get qrPayInstruction =>
      'Scan the QR code with your phone to complete payment.';

  @override
  String get qrPayWaiting => 'Waiting for payment…';

  @override
  String get qrPayExpired => 'Payment link expired';

  @override
  String get qrPayExpiredBody =>
      'The QR code has expired. Please go back and try again.';

  @override
  String get qrPayCancel => 'Cancel';

  @override
  String get qrPayGoBack => 'Go Back';

  @override
  String get qrNeedsConnectionTitle => 'No connection';

  @override
  String get qrNeedsConnectionBody =>
      'This payment method needs the internet. Check the connection and try again, or choose another payment method.';

  @override
  String get qrOrderRefusedBody =>
      'The order could not be sent to the server. Please choose another payment method or ask staff.';

  @override
  String get qrPayCancelConfirm => 'Cancel this payment and go back?';

  @override
  String get qrPayCancelContinue => 'Keep Waiting';

  @override
  String qrPayExpiresIn(String minutes, String seconds) {
    return 'Expires in $minutes:$seconds';
  }
}
