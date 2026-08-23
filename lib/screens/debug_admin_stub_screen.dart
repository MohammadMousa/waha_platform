import 'package:flutter/material.dart';

import '../state/browsing_mode_service.dart';

/// Registered as a real route in app_router.dart but deliberately left out
/// of Routes.kioskAllowlist. If you land here, the guard let you through —
/// meaning you're in Normal mode (or the guard is broken; it should bounce
/// to Landing in both Kiosk and Shopping). If a nav attempt to this route
/// instead shows Landing while in Normal mode, something's wrong.
///
/// This exists purely so the navigation-lock claim is checkable. Before
/// this, any unlisted route fell back to Landing by default regardless of
/// mode, so there was no actual difference to observe between "blocked by
/// the guard" and "nothing else exists yet."
class DebugAdminStubScreen extends StatelessWidget {
  const DebugAdminStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug: Admin (stub)')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'You reached a route outside the navigation allowlist.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('Current mode: ${browsingModeService.mode.name}'),
              const SizedBox(height: 8),
              const Text(
                "If mode is kiosk or shopping and you're seeing this, the "
                "guard is not working — it should have bounced you to "
                "Landing instead. Only Normal mode should ever land here.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
