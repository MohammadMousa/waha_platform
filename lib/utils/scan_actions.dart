import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../screens/camera_scan_screen.dart';
import '../services/api_exceptions.dart';
import '../services/local_prefs.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import 'locale_name.dart';

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
  // Block it with an explicit message instead.
  if (flow.orderId != null && flow.order?.status != 'PAID') {
    await showUnpaidOrderBlockedDialog(context);
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  try {
    final product = await flow.scanBarcode(barcode);
    if (LocalPrefs.showScanSuccessToast && context.mounted) {
      final name = localeName(product.name, localeService.locale.languageCode);
      messenger.showSnackBar(SnackBar(content: Text('Added: $name')));
    }
  } on ProductNotFoundException catch (e) {
    if (context.mounted) await showBlockingScanError(context, e.message);
  } on ProductNotSellableException catch (e) {
    if (context.mounted) await showBlockingScanError(context, e.message);
  } catch (e) {
    if (context.mounted) await showBlockingScanError(context, 'Scan failed: $e');
  }
}

/// Blocks a scan attempt while an order has been placed but not yet paid —
/// shown instead of silently adding to (or failing to add to) a cart that
/// no longer reflects what's being paid for.
Future<void> showUnpaidOrderBlockedDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.info_outline, color: Colors.orange),
      title: Text(l10n.scanBlockedUnpaidTitle),
      content: Text(l10n.scanBlockedUnpaidMessage),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// A dialog the user must tap through, not a toast that can be missed —
/// this is what stands between a rejected/not-found scan and the customer
/// walking away thinking it was added. Shared with simulator_overlay.dart's
/// fake-scan buttons so every scan-failure path behaves the same way.
Future<void> showBlockingScanError(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.error_outline, color: Colors.red),
      title: const Text('Scan failed'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
