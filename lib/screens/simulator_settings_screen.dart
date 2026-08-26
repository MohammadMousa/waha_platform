import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/app_router.dart';
import '../state/simulator_service.dart';

class SimulatorSettingsScreen extends StatefulWidget {
  const SimulatorSettingsScreen({super.key});

  @override
  State<SimulatorSettingsScreen> createState() =>
      _SimulatorSettingsScreenState();
}

class _SimulatorSettingsScreenState extends State<SimulatorSettingsScreen> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final codes =
        context.read<SimulatorService>().cachedCodes(SimScanType.product);
    _controllers = codes.isEmpty
        ? [TextEditingController()]
        : codes.map((c) => TextEditingController(text: c)).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addField() {
    setState(() => _controllers.add(TextEditingController()));
  }

  void _removeField(int index) {
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
      if (_controllers.isEmpty) _controllers.add(TextEditingController());
    });
  }

  void _save() {
    final codes = _controllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    context.read<SimulatorService>().setCachedCodes(SimScanType.product, codes);
    final msg = codes.isEmpty
        ? 'Cleared'
        : 'Saved ${codes.length} code${codes.length == 1 ? '' : 's'}';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<SimulatorService>();
    final scheme = Theme.of(context).colorScheme;

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
          const SizedBox(height: 20),

          // ── Product UPC codes ──────────────────────────────────────────
          Text('Product UPC codes',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Tap the scan button fires a random code from this list. '
            'Long-press the button to set a one-off code immediately.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),

          for (var i = 0; i < _controllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controllers[i],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'UPC ${i + 1}',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.remove_circle_outline,
                        color: scheme.error),
                    onPressed: () => _removeField(i),
                  ),
                ],
              ),
            ),

          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add code'),
            onPressed: _addField,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),

          const Divider(height: 40),
          Text(
            'Coupon and Wallet codes aren\'t here yet — nothing on the '
            'backend consumes them in this phase.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const Divider(height: 32),
          Text(
            'Test the navigation lock: navigates to a route outside the '
            'allowlist. Kiosk/Shopping mode bounces back; Normal lands.',
            style: TextStyle(color: scheme.onSurfaceVariant),
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
