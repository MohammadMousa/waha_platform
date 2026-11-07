import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/app_messenger.dart';

/// The Arabic or English reason for a server coupon error code, one text per
/// code. An unknown code gets the general text.
String couponErrorText(AppLocalizations l, String code) => switch (code) {
      'COUPON_NOT_FOUND' => l.couponErrNotFound,
      'COUPON_DISABLED' => l.couponErrDisabled,
      'COUPON_NOT_YET_VALID' => l.couponErrNotYetValid,
      'COUPON_EXPIRED' => l.couponErrExpired,
      'COUPON_WRONG_STORE' => l.couponErrWrongStore,
      'COUPON_USAGE_LIMIT_REACHED' => l.couponErrUsageLimit,
      'COUPON_USER_LIMIT_REACHED' => l.couponErrUserLimit,
      'COUPON_AMOUNT_EXHAUSTED' => l.couponErrAmountExhausted,
      'COUPON_USER_AMOUNT_EXHAUSTED' => l.couponErrUserAmountExhausted,
      'COUPON_MINIMUM_ORDER_NOT_MET' => l.couponErrMinimum,
      'COUPON_NOT_COMBINABLE' => l.couponErrNotCombinable,
      'COUPON_NOT_APPLICABLE' => l.couponErrNotApplicable,
      _ => l.couponErrGeneric,
    };

/// A message at the bottom of the screen, replacing any one still showing.
void showCouponToast(String text, {bool problem = false}) {
  final m = rootScaffoldMessengerKey.currentState;
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: problem ? Colors.red.shade700 : null,
      duration: const Duration(seconds: 4),
    ));
}
