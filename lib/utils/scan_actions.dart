import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/camera_scan_screen.dart';
import '../services/api_exceptions.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import 'locale_name.dart';

/// Pushes the camera scanner, and on a successful detection, adds it to
/// the cart — the same action the Shopping-mode CTA on Landing/Cart uses.
/// Shared here so both call sites stay in sync rather than duplicating
/// the push-then-scan-then-report sequence.
Future<void> openCameraAndAddToCart(BuildContext context) async {
  final barcode = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const CameraScanScreen()),
  );
  if (barcode == null || !context.mounted) return;

  final flow = context.read<OrderFlowController>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    final product = await flow.scanBarcode(barcode);
    final name = localeName(product.name, localeService.locale.languageCode);
    messenger.showSnackBar(SnackBar(content: Text('Added: $name')));
  } on ProductNotFoundException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } on ProductNotSellableException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Scan failed: $e')));
  }
}
