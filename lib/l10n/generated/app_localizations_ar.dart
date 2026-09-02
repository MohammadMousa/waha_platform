// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'Waha';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navScan => 'مسح';

  @override
  String get navCart => 'السلة';

  @override
  String get navProfile => 'الملف الشخصي';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get navStores => 'المتاجر';

  @override
  String get landingHeadline => 'امسح منتجاتك للبدء';

  @override
  String get landingSubtitle =>
      'بدون حساب، بدون انتظار — التقط المنتجات من الرف وامسحها.';

  @override
  String get ctaStartScanning => 'ابدأ المسح';

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
  String get cartTotal => 'الإجمالي';

  @override
  String get checkoutButton => 'إتمام الشراء';

  @override
  String get payButton => 'ادفع';

  @override
  String get payRetry => 'إعادة محاولة الدفع';

  @override
  String get paymentDeclined => 'تم رفض الدفع';

  @override
  String get payNoMethods => 'لا توجد وسائل دفع متاحة';

  @override
  String get payNoMethodsSubtitle =>
      'يرجى التواصل مع الدعم أو المحاولة لاحقًا.';

  @override
  String get payAlreadyPaid => 'تم الدفع مسبقًا';

  @override
  String get successPaid => 'تم الدفع';

  @override
  String get successNewOrder => 'طلب جديد';

  @override
  String get successInvoiceQrLabel => 'امسح لعرض فاتورتك الإلكترونية';

  @override
  String get receiptTitle => 'الإيصال';

  @override
  String get settingsAppMode => 'وضع التطبيق';

  @override
  String get modeNormal => 'عادي';

  @override
  String get modeKiosk => 'كشك';

  @override
  String get modeShopping => 'تسوق';

  @override
  String get settingsKioskTimers => 'مؤقتات استرداد الكشك عند الخمول';

  @override
  String get settingsSaveTimers => 'حفظ المؤقتات';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get profileTitle => 'الملف الشخصي';

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
  String get authRegisterTitle => 'إنشاء حساب';

  @override
  String get authLoginTitle => 'تسجيل الدخول';

  @override
  String get authRegisterCta => 'إنشاء حساب';

  @override
  String get authLoginCta => 'تسجيل الدخول';

  @override
  String get authSwitchToLogin => 'لديك حساب بالفعل؟ سجّل الدخول';

  @override
  String get authSwitchToRegister => 'جديد هنا؟ أنشئ حسابًا';

  @override
  String get authRequiredError => 'اسم المستخدم وكلمة المرور مطلوبان';

  @override
  String get authPhoneLabel => 'رقم الهاتف';

  @override
  String get authSendOtp => 'إرسال الرمز';

  @override
  String get authAdminLogin => 'دخول المشرف';

  @override
  String get stores => 'المتاجر';

  @override
  String get storePickerTitle => 'اختر متجرًا';

  @override
  String get storePickerEmpty => 'لا توجد متاجر متاحة';

  @override
  String get storePickerSetDefault => 'تعيين كمتجر افتراضي';

  @override
  String get storePickerDefaultSetSuffix => 'تم تعيينه كمتجر افتراضي';

  @override
  String get storePickerGoToStore => 'الذهاب للمتجر';

  @override
  String get storePickerMakeDefault => 'تعيين افتراضي';

  @override
  String get storePickerIsDefault => 'افتراضي';

  @override
  String get storePickerCurrentStore => 'الحالي';

  @override
  String get storePickerRefreshStore => 'تحديث المتجر';

  @override
  String get storePickerRefreshed => 'تم تحديث المتجر';

  @override
  String get profileLoggedInPrefix => 'مسجّل الدخول باسم';

  @override
  String get profileGuestMessage =>
      'غير مسجّل الدخول — الشراء كضيف لا يزال يعمل.';

  @override
  String get profileLogout => 'تسجيل الخروج';

  @override
  String get profileLogin => 'تسجيل الدخول';

  @override
  String get profileRegister => 'إنشاء حساب';

  @override
  String get profileChangeStore => 'تغيير المتجر';

  @override
  String get profileNoStoreSelected => 'لم يتم اختيار متجر';

  @override
  String get navOrders => 'طلباتي';

  @override
  String get navSearch => 'بحث';

  @override
  String get navCategories => 'التصنيفات';

  @override
  String get ordersTitle => 'طلباتي';

  @override
  String get ordersEmpty => 'لا طلبات بعد.';

  @override
  String get ordersLoginPrompt => 'سجّل الدخول لعرض سجل طلباتك.';

  @override
  String get searchTitle => 'البحث';

  @override
  String get searchHint => 'ابحث عن منتجات...';

  @override
  String get searchComingSoon => 'البحث قادم قريبًا.';

  @override
  String get categoriesTitle => 'التصنيفات';

  @override
  String get categoriesComingSoon => 'التصنيفات قادمة قريبًا.';

  @override
  String get viewCart => 'عرض السلة';

  @override
  String get homeSearchHint => 'ماذا تبحث عن؟';

  @override
  String get homeProducts => 'المنتجات';

  @override
  String get checkoutCreating => 'جاري إنشاء طلبك...';

  @override
  String get checkoutSelectPayment => 'اختر وسيلة الدفع';

  @override
  String get checkoutOrderSummary => 'ملخص الطلب';

  @override
  String get seeAll => 'عرض الكل';

  @override
  String get recentlyAdded => 'أحدث المنتجات';

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
  String get invoiceDownloadPdf => 'تحميل الفاتورة';

  @override
  String get invoiceDetails => 'تفاصيل الفاتورة';

  @override
  String get invoiceItems => 'المنتجات';

  @override
  String get invoiceRef => 'المرجع';

  @override
  String get invoiceDate => 'التاريخ';

  @override
  String get invoiceStatusLabel => 'الحالة';

  @override
  String get invoiceOrderNum => 'الطلب';

  @override
  String get invoiceNewOrder => 'طلب جديد';

  @override
  String get invoiceQrHint => 'امسح للفتح في هاتفك';

  @override
  String get invoiceClosingSoon => 'الشاشة تغلق خلال';

  @override
  String get payConfirm => 'تأكيد الدفع';

  @override
  String get payProcessing => 'جاري معالجة الدفع...';

  @override
  String get payWaiting => 'في انتظار تأكيد الدفع...';

  @override
  String get payCheckNow => 'دفعت — تحقق الآن';

  @override
  String get payOpenedBrowser => 'أكمل الدفع في التبويب الذي فُتح.';

  @override
  String get language => 'اللغة';

  @override
  String get shareInvoice => 'مشاركة الفاتورة';

  @override
  String get shareCopyLink => 'نسخ الرابط';

  @override
  String get shareLinkCopied => 'تم نسخ الرابط';

  @override
  String get cartClearTitle => 'مسح السلة؟';

  @override
  String get cartClearMessage => 'سيتم إزالة جميع المنتجات من السلة.';

  @override
  String get cartClearConfirm => 'مسح';

  @override
  String get cartClearCancel => 'إلغاء';

  @override
  String get perUnit => 'للوحدة';

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
  String get invoiceDueLabel => 'المستحق';

  @override
  String get adminPaymentMethods => 'وسائل الدفع';

  @override
  String get adminPaymentMethodsHint =>
      'تفعيل أو تعطيل وسائل الدفع لهذا المتجر.';

  @override
  String get adminPaymentMethodsSaving => 'جارٍ الحفظ…';

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
