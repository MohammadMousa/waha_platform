import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  final flow = context.read<OrderFlowController>();
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
