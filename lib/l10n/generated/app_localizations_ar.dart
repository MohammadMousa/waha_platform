// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get timeJustNow => 'الآن';

  @override
  String timeAgo(String t) {
    return 'منذ $t';
  }

  @override
  String timeDays(String n) {
    return '$n ي';
  }

  @override
  String timeHours(String n) {
    return '$n س';
  }

  @override
  String timeMinutes(String n) {
    return '$n د';
  }

  @override
  String timeSeconds(String n) {
    return '$n ث';
  }

  @override
  String get timeAm => 'ص';

  @override
  String get timePm => 'م';

  @override
  String offlineLastAttempt(String when) {
    return 'آخر محاولة: $when';
  }

  @override
  String ordersLastAttempt(String when) {
    return 'آخر محاولة إرسال: $when';
  }

  @override
  String offlineLastPull(String when) {
    return 'آخر تحميل ناجح: $when';
  }

  @override
  String ordersLastAccepted(String when) {
    return 'آخر قبول من الخادم: $when';
  }

  @override
  String get appTitle => 'Waha';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navCart => 'السلة';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get landingHeadline => 'امسح منتجاتك للبدء';

  @override
  String get landingSubtitle =>
      'بدون حساب، بدون انتظار — التقط المنتجات من الرف وامسحها.';

  @override
  String get ctaContinueShopping => 'متابعة التسوق';

  @override
  String get cartTitle => 'السلة';

  @override
  String get cartEmptyTitle => 'السلة فارغة';

  @override
  String get cartEmptySubtitle => 'امسح منتجًا لإضافته هنا.';

  @override
  String get cartSubtotal => 'المجموع الفرعي';

  @override
  String get cartTax => 'الضريبة';

  @override
  String get cartDiscount => 'الخصم';

  @override
  String get cartBeforeDiscount => 'قبل الخصم';

  @override
  String get cartZeroDueHint => 'أضف المزيد من المنتجات للاستفادة من العرض';

  @override
  String get cartTotal => 'الإجمالي';

  @override
  String get checkoutButton => 'الشراء والدفع';

  @override
  String get devicePinDialogTitle => 'إعدادات الجهاز';

  @override
  String get devicePinSignedInAs => 'تم الدخول باسم';

  @override
  String get devicePinLabel => 'أدخل رمز PIN الخاص بالجهاز';

  @override
  String get devicePinUnlock => 'فتح';

  @override
  String get commonOk => 'حسنًا';

  @override
  String get scanFailedTitle => 'فشل المسح';

  @override
  String scanNotFoundMessage(String barcode) {
    return 'لم يتم العثور على منتج بهذا الباركود: $barcode';
  }

  @override
  String get scanNotSellableMessage => 'هذا المنتج غير متاح للبيع حاليًا.';

  @override
  String get offlineNotReady =>
      'لا يزال تحميل المنتجات جاريًا، يرجى الانتظار قليلًا.';

  @override
  String get couponErrNotFound => 'رمز القسيمة غير صالح.';

  @override
  String get couponErrDisabled => 'هذه القسيمة غير مفعّلة.';

  @override
  String get couponErrNotYetValid => 'هذه القسيمة لم يبدأ سريانها بعد.';

  @override
  String get couponErrExpired => 'انتهت صلاحية هذه القسيمة.';

  @override
  String get couponErrWrongStore => 'هذه القسيمة غير صالحة في هذا الفرع.';

  @override
  String get couponErrUsageLimit => 'استُنفد الحد الأقصى لاستخدام هذه القسيمة.';

  @override
  String get couponErrUserLimit => 'وصلت إلى الحد الأقصى لاستخدام هذه القسيمة.';

  @override
  String get couponErrAmountExhausted =>
      'استُنفد مبلغ الخصم المتاح لهذه القسيمة.';

  @override
  String get couponErrUserAmountExhausted =>
      'استنفدت مبلغ الخصم المتاح لك بهذه القسيمة.';

  @override
  String get couponErrMinimum => 'قيمة السلة أقل من الحد الأدنى لهذه القسيمة.';

  @override
  String get couponErrNotCombinable =>
      'لا يمكن الجمع بين هذه القسيمة والعروض الحالية.';

  @override
  String get couponErrNotApplicable =>
      'لا يوجد في السلة ما تنطبق عليه هذه القسيمة.';

  @override
  String get couponErrGeneric => 'تعذّر تطبيق القسيمة.';

  @override
  String couponApplied(String code) {
    return 'تم تطبيق القسيمة $code';
  }

  @override
  String couponRejected(String code, String reason) {
    return 'القسيمة $code: $reason';
  }

  @override
  String couponDropped(String code, String reason) {
    return 'تمت إزالة القسيمة $code: $reason';
  }

  @override
  String get couponStage => 'لا يمكن إضافة قسيمة في هذه المرحلة';

  @override
  String get couponNeedItems => 'أضف بعض المنتجات إلى السلة أولاً';

  @override
  String get couponCheckFailed =>
      'تعذّر الوصول إلى الخادم، لذلك لا يمكن التحقق من القسيمة. حاول مرة أخرى عند الاتصال.';

  @override
  String cartCoupon(String code) {
    return 'قسيمة $code';
  }

  @override
  String get cartCouponRemove => 'إزالة القسيمة';

  @override
  String get offlineDataTitle => 'البيانات دون اتصال';

  @override
  String offlineRows(String feed, String count) {
    return '$feed: $count سجل';
  }

  @override
  String get offlineFullDone => '(تم التحميل الكامل)';

  @override
  String get offlineNotComplete => '(غير مكتمل)';

  @override
  String offlineCursor(String since, String afterId) {
    return 'المؤشر $since / $afterId';
  }

  @override
  String offlineErrorLine(String error) {
    return 'خطأ: $error';
  }

  @override
  String get offlinePullNow => 'تحميل الآن';

  @override
  String get offlinePulling => 'جارٍ التحميل…';

  @override
  String offlineLastResult(String time, String message) {
    return 'آخر نتيجة ($time): $message';
  }

  @override
  String pullDone(String count) {
    return 'اكتمل التحميل: تم تحديث $count سجل';
  }

  @override
  String pullFailed(String error) {
    return 'فشل التحميل: $error';
  }

  @override
  String get pullNoSession => 'تم التخطي: الجهاز غير مسجّل الدخول';

  @override
  String get pullCustomerActive =>
      'تم التخطي: الشاشة قيد الاستخدام. حاول مرة أخرى عند الخمول.';

  @override
  String get pullBusy => 'هناك تحميل قيد التنفيذ…';

  @override
  String pullServerBusy(String seconds) {
    return 'توقف التحميل: طلب الخادم الانتظار $seconds ثانية';
  }

  @override
  String get pullAuthStopped =>
      'توقف التحميل: رفض الخادم تسجيل دخول هذا الجهاز';

  @override
  String ordersTitle(String pending, String dead) {
    return 'طلبات للإرسال ($pending بالانتظار، $dead فاشلة)';
  }

  @override
  String get ordersAuthStopped => 'توقف الإرسال: رفض الخادم جلسة هذا الجهاز.';

  @override
  String get ordersAuthStoppedHint =>
      'الطلبات محفوظة وسيتم إرسالها بعد تسجيل دخول الجهاز من جديد.';

  @override
  String get ordersNoFailed => 'لا توجد طلبات فاشلة.';

  @override
  String ordersTotal(String ref, String amount, String currency) {
    return '$ref   الإجمالي $amount $currency';
  }

  @override
  String ordersMade(String at) {
    return 'أُنشئ $at';
  }

  @override
  String get ordersRetry => 'إعادة المحاولة';

  @override
  String get ordersSendNow => 'إرسال الآن';

  @override
  String get ordersSending => 'جارٍ الإرسال…';

  @override
  String sendDone(String count) {
    return 'تم إرسال $count طلب(ات) إلى الخادم';
  }

  @override
  String get sendNothing => 'لا يوجد ما ينتظر الإرسال';

  @override
  String sendPartial(String sent, String rejected) {
    return 'تم إرسال $sent؛ ورفض الخادم $rejected (انظر قائمة الفاشلة)';
  }

  @override
  String sendRejected(String rejected) {
    return 'رفض الخادم $rejected طلب(ات) (انظر قائمة الفاشلة)';
  }

  @override
  String sendFailed(String error) {
    return 'فشل الإرسال: $error';
  }

  @override
  String get sendNoSession => 'تم تخطي الإرسال: الجهاز غير مسجّل الدخول';

  @override
  String get sendAuthStopped =>
      'توقف الإرسال: رفض الخادم تسجيل دخول هذا الجهاز';

  @override
  String get sendBusy => 'الإرسال قيد التنفيذ…';

  @override
  String scanFailedMessage(String error) {
    return 'فشل المسح: $error';
  }

  @override
  String get scanBlockedUnpaidTitle => 'لم يتم الدفع بعد';

  @override
  String get scanBlockedUnpaidMessage =>
      'لم تدفع قيمة هذا الطلب بعد. يرجى إتمام الدفع أولاً.';

  @override
  String get settingsShowCartMenuKiosk => 'إظهار قائمة السلة في وضع الكشك';

  @override
  String get paymentDeclined => 'تم رفض الدفع';

  @override
  String get payNoMethods => 'لا توجد وسائل دفع متاحة';

  @override
  String get successPaid => 'تم الدفع';

  @override
  String get successNewOrder => 'طلب جديد';

  @override
  String get successInvoiceQrLabel => 'امسح لعرض فاتورتك الإلكترونية';

  @override
  String get receiptTitle => 'الإيصال';

  @override
  String get settingsKioskTimers => 'مؤقتات استرداد الكشك عند الخمول';

  @override
  String get settingsSaveTimers => 'حفظ المؤقتات';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get navBrowse => 'تصفح';

  @override
  String get browseTitle => 'المنتجات';

  @override
  String get browseEmpty => 'لا توجد منتجات لهذا المتجر.';

  @override
  String get browseLoadError => 'تعذر تحميل المنتجات.';

  @override
  String get browseRetry => 'إعادة المحاولة';

  @override
  String get browseLoadMore => 'تحميل المزيد';

  @override
  String get productDetailAddToCart => 'أضف إلى السلة';

  @override
  String get productDetailUnavailable => 'غير متاح حاليًا';

  @override
  String get authUsername => 'اسم المستخدم';

  @override
  String get authPassword => 'كلمة المرور';

  @override
  String get authLoginCta => 'تسجيل الدخول';

  @override
  String get authRequiredError => 'اسم المستخدم وكلمة المرور مطلوبان';

  @override
  String get authDeviceLogin => 'دخول الجهاز';

  @override
  String get authPinCode => 'الرمز السري';

  @override
  String get authDeviceLoginSubtitle =>
      'سجّل الدخول بحساب الكشك الخاص بهذا الجهاز';

  @override
  String get stores => 'المتاجر';

  @override
  String get profileLogout => 'تسجيل الخروج';

  @override
  String get profileLogoutFailed =>
      'تعذّر تسجيل الخروج. تحقّق من الاتصال وحاول مرة أخرى.';

  @override
  String get profileLogin => 'تسجيل الدخول';

  @override
  String get profileNoStoreSelected => 'لم يتم اختيار متجر';

  @override
  String get searchTitle => 'البحث';

  @override
  String get searchHint => 'ابحث عن منتجات...';

  @override
  String get categoriesTitle => 'التصنيفات';

  @override
  String get viewCart => 'عرض السلة';

  @override
  String get checkoutCreating => 'جاري إنشاء طلبك...';

  @override
  String get invoiceTitle => 'الفاتورة';

  @override
  String get invoicePaid => 'مدفوع';

  @override
  String get invoiceUnpaid => 'غير مدفوع';

  @override
  String get invoicePending => 'قيد الانتظار';

  @override
  String get invoiceCancelled => 'ملغى';

  @override
  String invoicePaidVia(String method) {
    return 'تم الدفع عبر $method';
  }

  @override
  String get invoiceSelectPayment => 'اختر وسيلة الدفع';

  @override
  String get invoiceItems => 'المنتجات';

  @override
  String get invoiceOrderNum => 'الطلب';

  @override
  String get invoiceNewOrder => 'طلب جديد';

  @override
  String get payConfirm => 'تأكيد الدفع';

  @override
  String get payWaiting => 'في انتظار تأكيد الدفع...';

  @override
  String get payCheckNow => 'دفعت — تحقق الآن';

  @override
  String get payOpenedBrowser => 'أكمل الدفع في التبويب الذي فُتح.';

  @override
  String get language => 'اللغة';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get perUnit => 'للوحدة';

  @override
  String get priceInclVat => 'شامل الضريبة';

  @override
  String get priceExclVat => 'غير شامل الضريبة';

  @override
  String get kioskIdleTitle => 'هل لا تزال هنا؟';

  @override
  String kioskIdleBeforeBody(int seconds) {
    return 'ستُعاد تهيئة الجلسة خلال $seconds ثوانٍ.';
  }

  @override
  String kioskIdleAfterBody(int seconds) {
    return 'ستُغلق هذه الشاشة خلال $seconds ثوانٍ.';
  }

  @override
  String get kioskIdleContinue => 'متابعة';

  @override
  String get kioskIdleNewOrder => 'بدء طلب جديد';

  @override
  String get kioskPaidTitle => 'تم استلام الدفع';

  @override
  String get kioskPaidScanHint => 'امسح لفتح الفاتورة الإلكترونية';

  @override
  String kioskPaidClosingIn(int seconds) {
    return 'تغلق الشاشة خلال $seconds ث';
  }

  @override
  String get kioskPaidResetTimer => 'أعطني مزيداً من الوقت';

  @override
  String get kioskPaidNewOrder => 'طلب جديد';

  @override
  String get terminalTitle => 'جهاز الدفع';

  @override
  String get terminalConnecting => 'جارٍ الاتصال بجهاز الدفع…';

  @override
  String get terminalNotConnected => 'جهاز الدفع غير متصل — تحقق من كابل USB.';

  @override
  String get terminalSwipeCard => 'مرر أو قرّب البطاقة على جهاز الدفع';

  @override
  String terminalPreviousPaymentPending(int seconds) {
    return 'جارٍ تجهيز جهاز الدفع. يرجى الانتظار $seconds ثانية…';
  }

  @override
  String get terminalNotReady =>
      'جهاز الدفع غير جاهز. يرجى المحاولة بعد قليل أو طلب المساعدة من الموظف.';

  @override
  String autoRestartMessage(int seconds) {
    return 'إعادة التشغيل خلال $seconds ثانية';
  }

  @override
  String get autoRestartNotNow => 'ليس الآن';

  @override
  String get autoRestartNow => 'أعد التشغيل الآن';

  @override
  String terminalBusyTryLater(int seconds) {
    return 'جهاز الدفع غير جاهز. يرجى المحاولة مرة أخرى بعد $seconds ثوانٍ.';
  }

  @override
  String terminalSessionStartFailed(String error) {
    return 'فشل بدء الجلسة: $error';
  }

  @override
  String terminalApprovedNotRecorded(String error) {
    return 'تمت الموافقة على الجهاز لكن تعذّر تسجيلها ($error) — لا تُعد المحاولة، تواصل مع الدعم.';
  }

  @override
  String get terminalPaymentFailedTitle => 'فشلت عملية الدفع';

  @override
  String get terminalResultUnknownTitle => 'نتيجة الدفع غير معروفة';

  @override
  String get terminalResultUnknown =>
      'لم يرد جهاز البطاقة في الوقت المحدد. لا تدفع مرة أخرى الآن — يرجى الطلب من الموظف التحقق من الجهاز أولاً.';

  @override
  String get terminalClose => 'إغلاق';

  @override
  String autoSelectingIn(int seconds) {
    return 'الاختيار التلقائي خلال $seconds ث — اضغط للدفع الآن';
  }

  @override
  String get invoiceDueLabel => 'المستحق';

  @override
  String get mobilePaymentScanHint => 'امسح للدفع عبر هاتفك';

  @override
  String get mobilePaymentPolling => 'في انتظار الدفع…';

  @override
  String get qrPayTitle => 'امسح للدفع';

  @override
  String get qrPayInstruction =>
      'امسح رمز الاستجابة السريعة بهاتفك لإتمام الدفع.';

  @override
  String get qrPayWaiting => 'في انتظار الدفع…';

  @override
  String get qrPayExpired => 'انتهت صلاحية رابط الدفع';

  @override
  String get qrPayExpiredBody =>
      'انتهت صلاحية رمز الاستجابة السريعة. يرجى العودة والمحاولة مرة أخرى.';

  @override
  String get qrPayConfirmed => 'تم تأكيد الدفع';

  @override
  String get qrPayCancel => 'إلغاء';

  @override
  String get qrPayGoBack => 'العودة';

  @override
  String get qrPayCancelConfirm => 'إلغاء هذه العملية والعودة؟';

  @override
  String get qrPayCancelContinue => 'الاستمرار في الانتظار';

  @override
  String qrPayExpiresIn(String minutes, String seconds) {
    return 'تنتهي خلال $minutes:$seconds';
  }
}
