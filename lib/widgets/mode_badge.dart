import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/browsing_mode_service.dart';
import '../state/simulator_service.dart';

/// Small indicator of the current browsing mode. Stacked on every route in
/// app_router.dart. Bottom-left, away from the simulator cluster's bottom-right.
/// Hidden when dev tools are hidden (simulator eye-off button or startup default).
/// Tap 10 times anywhere on the landing page background to reveal.
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final bool hidden = AppConfig.simulatorAvailable &&
        context.watch<SimulatorService>().devToolsHidden;

    if (hidden) return const Positioned(bottom: 0, left: 0, child: SizedBox.shrink());

    final mode = context.watch<BrowsingModeService>().mode;
    final (label, color) = switch (mode) {
      BrowsingMode.normal => ('NORMAL', Colors.blueGrey),
      BrowsingMode.kiosk => ('KIOSK', Colors.deepOrange),
      BrowsingMode.shopping => ('SHOPPING', Colors.teal),
    };

    return Positioned(
      bottom: 16,
      left: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.92),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}
