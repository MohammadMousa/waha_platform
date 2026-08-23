import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/app_router.dart';
import '../state/order_flow_controller.dart';
import '../widgets/scan_capture_field.dart';
import '../widgets/waha_app_bar.dart';

/// Normal mode's explicit "Scan" entry. `ScanCaptureField` runs
/// invisibly here now, not as a visible typeable text box — a real
/// hardware scanner (USB/BT keyboard-wedge) still works exactly the same
/// underneath, but nothing on screen invites a customer to manually type
/// barcode digits. Manual entry is a dev/testing need, and that's
/// already covered by the Simulator overlay's Product-scan button — it
/// doesn't belong on a screen real customers see. Kiosk and Shopping
/// don't route through this screen at all: Kiosk captures scans
/// ambiently on Landing, Shopping opens the camera directly.
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OrderFlowController>();
    final itemCount = flow.cart.fold<int>(0, (sum, c) => sum + c.quantity);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const WahaAppBar(title: 'Scan'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          children: [
            // Invisible capture point for a real hardware scanner —
            // present and focused, never shown.
            const ScanCaptureField(visible: false),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer.withOpacity(0.6),
              ),
              child: Icon(Icons.qr_code_scanner, size: 44, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Ready to scan',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Point a barcode scanner at the item',
              style: TextStyle(color: scheme.outline),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: flow.cart.isEmpty
                  ? Center(
                      child: Text('No items scanned yet', style: TextStyle(color: scheme.outline)),
                    )
                  : ListView.builder(
                      itemCount: flow.cart.length,
                      itemBuilder: (context, i) {
                        final item = flow.cart[i];
                        return Card(
                          elevation: 0,
                          color: scheme.surfaceVariant.withOpacity(0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              child: Text(item.name.isNotEmpty ? item.name[0].toUpperCase() : '?'),
                            ),
                            title: Text(item.name),
                            trailing: Text('x${item.quantity}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.shopping_cart),
                label: Text('View Cart ($itemCount)'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: flow.cart.isEmpty
                    ? null
                    : () => Navigator.of(context).pushNamed(Routes.cart),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
