import 'package:flutter/material.dart';

import '../services/hardware_scanner_service.dart';
import '../utils/scan_actions.dart';

/// Mounted per-route (see app_router.dart) on every screen where scanning
/// makes sense, so a hardware barcode scanner keeps working no matter
/// where navigation takes the customer — not just on Landing. Renders
/// nothing; it only bridges [HardwareScannerService] scans into the same
/// add-to-cart handling the camera scanner uses.
class HardwareScanListener extends StatefulWidget {
  const HardwareScanListener({super.key});

  @override
  State<HardwareScanListener> createState() => _HardwareScanListenerState();
}

class _HardwareScanListenerState extends State<HardwareScanListener> {
  @override
  void initState() {
    super.initState();
    HardwareScannerService.instance.addListener(_onBarcode);
  }

  @override
  void dispose() {
    HardwareScannerService.instance.removeListener(_onBarcode);
    super.dispose();
  }

  void _onBarcode(String barcode) {
    if (!mounted) return;
    addScannedBarcodeToCart(context, barcode);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
