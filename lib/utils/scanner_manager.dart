import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../services/api_exceptions.dart';
import '../state/order_flow_controller.dart';
import 'coupon_text.dart';
import 'scan_actions.dart' show showUnpaidOrderBlockedDialog;

import '../screens/settings_screen.dart' show showCopyableTextDialog;
import '../services/geidea_terminal_bridge.dart';
import '../widgets/device_pin_dialog.dart';
import '../widgets/profile_sheet.dart';

/// THE single place every scan passes through before it is treated as a
/// product barcode: hardware scanner, camera AND the on-screen simulator all
/// make exactly ONE call, [handle]. Every scan rule belongs inside [handle]
/// (coupon, unpaid-order block, `cmd=` commands, anything added later) so a
/// new rule is one edit that reaches every scan path. NEVER add a second
/// public entry point or put a scan rule in a caller (scan_actions.dart,
/// simulator_overlay.dart): a rule outside [handle] is silently skipped by
/// whichever caller doesn't have it (this already happened once with coupons
/// and the simulator). A `cmd=` prefix marks a kiosk command instead of a
/// product code. A
/// `cmd=` prefix marks a kiosk command instead of a product code: e.g. a QR
/// sticker (content `cmd=upload-logs`) the client can scan to self-report
/// diagnostics without hunting for the Settings PIN. Add a new command only
/// to [_commands] below — nothing else needs to change as the list grows.
///
/// Commands here must stay read-only/diagnostic (nothing that changes kiosk
/// state) — a `cmd=` code is just printed text, anyone could scan it. A
/// command that needs to change something must go through the device PIN
/// dialog first, as `profile` does: the scan alone only asks for the PIN.
class ScannerManager {
  ScannerManager._();
  static final ScannerManager instance = ScannerManager._();

  static const _prefix = 'cmd=';

  final Map<String, Future<void> Function(BuildContext)> _commands = {
    'upload-logs': _uploadLogs,
    'profile': _profile,
  };

  static const _couponPrefix = 'coupon=';

  // The server's rule for a coupon code: 2 to 50 letters, digits, dot, dash
  // or underscore.
  static final _couponFormat = RegExp(r'^[A-Za-z0-9._-]{2,50}$');

  /// A scanned `coupon=<code>`, called only from [handle]. True when [code]
  /// was a coupon (handled, or refused with a message); false means "not mine".
  ///
  /// Where it is scanned: while an unpaid order is open (invoice screen) it is
  /// refused; with an empty cart the customer is asked to add items first;
  /// otherwise the server validates it. From the landing page an accepted
  /// coupon also opens the cart.
  Future<bool> _handleCoupon(BuildContext context, String code) async {
    if (!code.startsWith(_couponPrefix)) return false;
    final l = AppLocalizations.of(context)!;
    final flow = context.read<OrderFlowController>();
    final nav = Navigator.of(context);
    final value = code.substring(_couponPrefix.length).trim();

    if (flow.orderId != null && flow.order?.status != 'PAID') {
      showCouponToast(l.couponStage, problem: true);
      return true;
    }
    if (flow.cart.isEmpty) {
      showCouponToast(l.couponNeedItems, problem: true);
      return true;
    }
    if (!_couponFormat.hasMatch(value)) {
      showCouponToast(l.couponRejected(value, l.couponErrNotFound),
          problem: true);
      return true;
    }
    final onLanding = KioskRouteObserver.currentRouteName.value == Routes.landing;
    try {
      final q = await flow.applyCoupon(value);
      showCouponToast(l.couponApplied(q.coupon?.code ?? value));
      if (onLanding) nav.pushNamed(Routes.cart);
    } on CouponRejectedException catch (e) {
      showCouponToast(l.couponRejected(value, couponErrorText(l, e.code)),
          problem: true);
    } catch (_) {
      showCouponToast(l.couponCheckFailed, problem: true);
    }
    return true;
  }

  /// The one entry point for every scan. True means the scan was dealt with
  /// here (a coupon, a refusal, a command, or the unpaid-order block) and the
  /// caller must NOT also treat it as a product barcode. False means a normal
  /// barcode: the caller adds it to the cart.
  ///
  /// Order matters: a coupon comes first because on the invoice screen it has
  /// its own message ("coupons can't be added at this stage"); then, while an
  /// order is placed but unpaid, every other scan (product or `cmd=`) is
  /// blocked; then `cmd=` commands.
  Future<bool> handle(BuildContext context, String code) async {
    if (await _handleCoupon(context, code)) return true;
    if (!context.mounted) return true;
    final flow = context.read<OrderFlowController>();
    if (flow.orderId != null && flow.order?.status != 'PAID') {
      await showUnpaidOrderBlockedDialog(context);
      return true;
    }
    if (!code.startsWith(_prefix)) return false;
    final command = _commands[code.substring(_prefix.length)];
    if (command != null) await command(context);
    return true;
  }

  /// `cmd=profile`: the device PIN first (same check as the way into
  /// Settings); only a correct PIN opens the profile sheet, where the admin
  /// can sign out or change the account.
  static Future<void> _profile(BuildContext context) async {
    final unlocked = await showDialog<bool>(
      context: context,
      builder: (_) => const DevicePinDialog(),
    );
    if (unlocked != true || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ProfileSheet(),
    );
  }

  static Future<void> _uploadLogs(BuildContext context) async {
    final result = await GeideaTerminalBridge.instance.uploadLog();
    if (!context.mounted) return;
    // Same result dialog Settings' "Upload log" button already shows.
    await showCopyableTextDialog(
      context,
      'Upload log',
      GeideaTerminalBridge.describeUploadLogResult(result),
    );
  }
}
