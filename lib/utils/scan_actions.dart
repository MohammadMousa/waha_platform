import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../screens/camera_scan_screen.dart';
import '../services/api_exceptions.dart';
import '../router/app_router.dart';
import '../services/local_prefs.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import 'locale_name.dart';
import 'scanner_manager.dart';

/// Pushes the camera scanner, and on a successful detection, adds it to
/// the cart — the same action the Shopping-mode CTA on Landing/Cart uses.
/// Shared here so both call sites stay in sync rather than duplicating
/// the push-then-scan-then-report sequence.
///
/// Success is quiet by default — a footer toast only if
/// LocalPrefs.showScanSuccessToast is on (Dev Tools checkbox); the scan
/// sound is the normal confirmation. Failure is never quiet: a blocking
/// dialog the user must dismiss, so a rejected/not-found item can't be
/// missed and walked off with. Sound itself already fires from
/// OrderFlowController.scanBarcode/_addOrIncrement — not duplicated here.
Future<void> openCameraAndAddToCart(BuildContext context) async {
  final barcode = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const CameraScanScreen()),
  );
  if (barcode == null || !context.mounted) return;
  await addScannedBarcodeToCart(context, barcode);
}

/// Adds a scanned [barcode] to the cart with the shared scan UX: a quiet
/// optional toast on success, a blocking dialog on failure. Used by both
/// the camera flow above and the ambient hardware-scanner listener
/// (`HardwareScanListener`) so every scan path — camera or hardware —
/// looks and behaves identically to the customer.
Future<void> addScannedBarcodeToCart(BuildContext context, String barcode) async {
  final flow = context.read<OrderFlowController>();

  // An order has already been placed and isn't paid yet (customer is sitting
  // on the Invoice screen, or anywhere else mid-payment) — a scan here would
  // silently try to add to a cart that's no longer what's being paid for.
  // Block it with an explicit message instead. Applies to a `cmd=` scan too,
  // same as any other scan.
  if (flow.orderId != null && flow.order?.status != 'PAID') {
    await showUnpaidOrderBlockedDialog(context);
    return;
  }

  // A kiosk command (QR prefixed `cmd=`), not a product code — see
  // ScannerManager. Handled entirely there; never reaches product lookup.
  if (await ScannerManager.instance.handle(context, barcode)) return;
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final product = await flow.scanBarcode(barcode);
    if (LocalPrefs.showScanSuccessToast && context.mounted) {
      final name = localeName(product.name, localeService.locale.languageCode);
      messenger.showSnackBar(SnackBar(content: Text('Added: $name')));
    }
  } on ProductNotFoundException {
    if (context.mounted) await showScanNotFound(context, barcode);
  } on ProductNotSellableException {
    if (context.mounted) await showScanNotSellable(context);
  } catch (e) {
    if (context.mounted) await showScanFailed(context, '$e');
  }
}

/// Blocks a scan attempt while an order has been placed but not yet paid —
/// shown instead of silently adding to (or failing to add to) a cart that
/// no longer reflects what's being paid for.
Future<void> showUnpaidOrderBlockedDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return ScanNotice.show(
    context,
    icon: Icons.info_outline,
    color: Colors.orange,
    title: l10n.scanBlockedUnpaidTitle,
    message: l10n.scanBlockedUnpaidMessage,
  );
}

/// The scan failure dialogs. A dialog the user must tap through, not a toast
/// that can be missed — this is what stands between a rejected/not-found scan
/// and the customer walking away thinking it was added. Shared with
/// simulator_overlay.dart's fake-scan buttons so every scan-failure path
/// behaves the same way. Titles, buttons and messages are localized (the
/// server's own English text is no longer shown). Only ever one on screen —
/// see [ScanNotice].
Future<void> _showScanFailure(BuildContext context, String Function(AppLocalizations) message) {
  final l10n = AppLocalizations.of(context)!;
  return ScanNotice.show(
    context,
    icon: Icons.error_outline,
    color: Colors.red,
    title: l10n.scanFailedTitle,
    message: message(l10n),
  );
}

/// The scanned barcode matches no product.
Future<void> showScanNotFound(BuildContext context, String barcode) =>
    _showScanFailure(context, (l) => l.scanNotFoundMessage(barcode));

/// The product exists but cannot be sold right now.
Future<void> showScanNotSellable(BuildContext context) =>
    _showScanFailure(context, (l) => l.scanNotSellableMessage);

/// Any other failure, with the error text.
Future<void> showScanFailed(BuildContext context, String error) =>
    _showScanFailure(context, (l) => l.scanFailedMessage(error));

/// The one scan notice dialog. Scanning several unknown products in a row used
/// to stack a new dialog for each scan, all of which had to be dismissed one by
/// one. Now there is at most ONE on screen: a scan that fails while it is up
/// just replaces its text with the latest message. It is a named transient
/// route (Routes.scanError), so the idle timer keeps running underneath it.
class ScanNotice {
  ScanNotice._();

  static final ValueNotifier<_NoticeContent?> _content = ValueNotifier(null);
  static bool _showing = false;
  // The dialog's own context: if it is no longer mounted the dialog is gone
  // (e.g. its route was removed without popping), so a stuck flag can never
  // stop later notices from showing.
  static BuildContext? _dialogContext;

  /// True while the dialog is on screen.
  static bool get isShowing => _showing && (_dialogContext?.mounted ?? false);

  /// The message currently shown (tests and logging).
  static String? get currentMessage => _content.value?.message;

  static Future<void> show(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) async {
    final okLabel = AppLocalizations.of(context)!.commonOk;
    _content.value = _NoticeContent(icon, color, title, message);
    if (isShowing) return; // already on screen: only its text changed
    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        routeSettings: const RouteSettings(name: Routes.scanError),
        builder: (dialogContext) {
          _dialogContext = dialogContext;
          return ValueListenableBuilder<_NoticeContent?>(
            valueListenable: _content,
            builder: (_, c, __) => AlertDialog(
              icon: Icon(c?.icon ?? icon, color: c?.color ?? color),
              title: Text(c?.title ?? title),
              content: Text(c?.message ?? message),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(okLabel),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _showing = false;
      _dialogContext = null;
      _content.value = null;
    }
  }
}

class _NoticeContent {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  const _NoticeContent(this.icon, this.color, this.title, this.message);
}
