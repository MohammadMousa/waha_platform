import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/browsing_mode_service.dart';

/// Small, always-visible indicator of the current browsing mode. Stacked
/// on every route in app_router.dart — not just screens that use
/// WahaAppBar, since Cart/Checkout/Pay/Success/Settings/Profile all have
/// their own plain AppBars. Exists specifically so "which mode is this
/// running in" is answerable by looking at the screen, not by opening
/// Settings — bottom-left, away from the simulator cluster's bottom-right
/// spot and clear of every screen's own AppBar.
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key});

  @override
  Widget build(BuildContext context) {
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
