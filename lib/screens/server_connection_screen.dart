import 'package:flutter/material.dart';

import 'settings_screen.dart';

/// The Server Connection panel on its own screen, reachable before login
/// (opened from the startup connection popup, which sits above the router's
/// kiosk login gate). Same panel, same rules as in Settings.
class ServerConnectionScreen extends StatelessWidget {
  /// Force the Custom Connection switch to this position when opening
  /// (null = the saved one).
  final bool? customOn;

  const ServerConnectionScreen({super.key, this.customOn});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server Connection')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ServerConnectionPanel(
              initiallyExpanded: true,
              initialCustomOn: customOn,
            ),
          ],
        ),
      ),
    );
  }
}
