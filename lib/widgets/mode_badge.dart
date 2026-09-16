import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/browsing_mode_service.dart';
import '../state/simulator_service.dart';

/// Small indicator of the current browsing mode. Stacked on every route in
/// app_router.dart. Bottom-left, away from the simulator cluster's bottom-right.
/// Hidden when dev tools are hidden (simulator eye-off button or startup
/// default). Purely a display widget, not tappable (see IgnorePointer below)
/// — to bring dev tools back, use the cart screen's 10-tap gesture or the
/// Simulator switch in Settings' Developer Tools panel.
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    // devToolsHidden already defaults to true (hidden) on a fresh install
    // regardless of whether the simulator feature is compiled in — gating
    // on AppConfig.simulatorAvailable here meant this expression was always
    // false (badge stuck permanently visible) on any build with
    // ENABLE_SIMULATOR=false, i.e. every real release build.
    final bool hidden = context.watch<SimulatorService>().devToolsHidden;

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
