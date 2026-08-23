import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../router/app_router.dart';
import '../screens/camera_scan_screen.dart';
import '../screens/settings_screen.dart';
import '../services/api_exceptions.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/simulator_service.dart';
import '../utils/locale_name.dart';
import 'manual_code_dialog.dart';

/// The floating button cluster from the reference screenshot, reworked as
/// tap-targets instead of a settings sub-panel: Close / Home / Settings /
/// Camera / Product. Sits above every screen via a Stack in main.dart, not
/// tied to any one route, so it works regardless of where the user is —
/// which is the point of a dev tool: skip screens, don't require being on
/// the "right" one first.
///
/// Compiled out entirely when AppConfig.simulatorAvailable is false — see
/// that flag's docs on why release builds shouldn't just hide this behind
/// a settings toggle.
class SimulatorOverlay extends StatelessWidget {
  const SimulatorOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.simulatorAvailable) return const SizedBox.shrink();

    final sim = context.watch<SimulatorService>();
    if (!sim.clusterVisible) {
      return Positioned(
        bottom: 16,
        right: 16,
        child: _ReopenChip(onTap: sim.showCluster),
      );
    }

    return Positioned(
      bottom: 16,
      right: 16,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(28),
        color: Colors.black87,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconBtn(icon: Icons.close, tooltip: 'Close', onTap: sim.hideCluster),
              _IconBtn(
                icon: Icons.home,
                tooltip: 'Home',
                onTap: () => _goHome(context),
              ),
              _IconBtn(
                icon: Icons.settings,
                tooltip: 'Settings',
                // Straight to the real Settings screen, not the dev
                // simulator's own — this used to go the other way round
                // (gear → Simulator Settings → a link out to real
                // Settings), which was backwards: you want app config
                // first, dev tooling is the nested, secondary thing, not
                // the gate you have to walk through to reach it. Scan-code
                // simulator settings are now reachable *from* Settings
                // instead — see settings_screen.dart's Developer Tools link.
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              _IconBtn(
                icon: Icons.camera_alt,
                tooltip: 'Scan with camera',
                onTap: () => _openCamera(context),
              ),
              _ScanTypeBtn(
                type: SimScanType.product,
                icon: Icons.qr_code,
                tooltip: 'Product scan',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goHome(BuildContext context) {
    // Dev shortcut: unconditional reset + jump to Landing, regardless of
    // what's mid-flight (mid-scan, non-empty cart, checkout in progress).
    // Not the same action as a real customer-facing "start over" — see
    // OrderFlowController.reset() docs.
    context.read<OrderFlowController>().reset();
    Navigator.of(context).pushNamedAndRemoveUntil(
      Routes.landing,
      (route) => false,
    );
  }

  Future<void> _openCamera(BuildContext context) async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraScanScreen()),
    );
    if (barcode != null && context.mounted) {
      await _fireScan(context, barcode);
    }
  }

  static Future<void> _fireScan(BuildContext context, String code) async {
    final flow = context.read<OrderFlowController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final product = await flow.scanBarcode(code);
      final name = localeName(product.name, localeService.locale.languageCode);
      messenger.showSnackBar(SnackBar(content: Text('Scanned: $name')));
    } on ProductNotFoundException {
      messenger.showSnackBar(SnackBar(content: Text('No product for code $code')));
    } on ProductNotSellableException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Scan failed: $e')));
    }
  }
}

class _ScanTypeBtn extends StatelessWidget {
  final SimScanType type;
  final IconData icon;
  final String tooltip;

  const _ScanTypeBtn({required this.type, required this.icon, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<SimulatorService>();
    return GestureDetector(
      onLongPress: () => _openManualEntry(context, sim),
      child: _IconBtn(
        icon: icon,
        tooltip: '$tooltip (tap: fire cached, long-press: set code)',
        onTap: () async {
          final cached = sim.cachedCode(type);
          if (cached == null || cached.isEmpty) {
            // Nothing cached yet — go straight to manual entry rather than
            // firing a blank code or silently doing nothing.
            await _openManualEntry(context, sim);
          } else {
            await SimulatorOverlay._fireScan(context, cached);
          }
        },
      ),
    );
  }

  Future<void> _openManualEntry(BuildContext context, SimulatorService sim) async {
    final code = await showManualCodeDialog(context, title: 'Set Product Code');
    if (code == null || code.isEmpty) return;
    sim.setCachedCode(type, code);
    if (context.mounted) {
      await SimulatorOverlay._fireScan(context, code);
    }
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}

class _ReopenChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ReopenChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: Colors.black54,
      child: IconButton(
        icon: const Icon(Icons.bug_report, color: Colors.white),
        tooltip: 'Show simulator',
        onPressed: onTap,
      ),
    );
  }
}
