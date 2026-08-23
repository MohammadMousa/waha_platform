import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/app_router.dart';
import '../state/simulator_service.dart';

class SimulatorSettingsScreen extends StatelessWidget {
  const SimulatorSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<SimulatorService>();
    final productController = TextEditingController(
      text: sim.cachedCode(SimScanType.product) ?? '',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Simulator Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Enable Simulator'),
            value: sim.enabled,
            onChanged: sim.setEnabled,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: productController,
            decoration: const InputDecoration(
              labelText: 'Product Code (UPC)',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) =>
                sim.setCachedCode(SimScanType.product, value.trim()),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => sim.setCachedCode(
                SimScanType.product,
                productController.text.trim(),
              ),
              child: const Text('Save'),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Coupon and Wallet codes aren\'t here yet — nothing on the '
            'backend consumes them in this phase.',
            style: TextStyle(color: Colors.grey),
          ),
          const Divider(height: 32),
          const Text(
            'Test the navigation lock: this navigates to a route that '
            'exists but is deliberately left out of the allowlist. In '
            'Kiosk or Shopping mode you should bounce straight back to '
            'Landing. Only in Normal mode should you actually land on it.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.lock_outline),
            label: const Text('Try disallowed route (lock test)'),
            onPressed: () =>
                Navigator.of(context).pushNamed(Routes.debugAdminStub),
          ),
        ],
      ),
    );
  }
}
