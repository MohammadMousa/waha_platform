import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../state/startup_connection.dart';

/// Blocks the app behind a "Connecting…" card while the server is
/// unreachable at startup (see [StartupConnection]). Sits above the Navigator
/// on purpose so it covers every route; it needs no Overlay of its own.
class ConnectionGateOverlay extends StatelessWidget {
  final Widget child;
  const ConnectionGateOverlay({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: startupConnection,
      builder: (context, _) {
        final show = startupConnection.active && !startupConnection.suspended;
        return Stack(
          children: [
            child,
            if (show) const Positioned.fill(child: _GateCard()),
          ],
        );
      },
    );
  }
}

class _GateCard extends StatefulWidget {
  const _GateCard();

  @override
  State<_GateCard> createState() => _GateCardState();
}

class _GateCardState extends State<_GateCard> {
  // Hidden way in: 15 quick taps on the title, each within 1 s of the last.
  static const _tapsNeeded = 15;
  static const _maxGap = Duration(seconds: 1);
  int _taps = 0;
  DateTime? _last;

  void _onTitleTap() {
    final now = DateTime.now();
    _taps =
        (_last != null && now.difference(_last!) <= _maxGap) ? _taps + 1 : 1;
    _last = now;
    if (_taps >= _tapsNeeded) {
      _taps = 0;
      startupConnection.openConnectionScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = startupConnection;
    final custom = AppConfig.isCustomConnectionActive;

    return Material(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTitleTap,
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 12),
                        Text('Connecting to server…',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    AppConfig.apiBaseUrl,
                    textDirection: TextDirection.ltr,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  if (s.lastError != null) ...[
                    const SizedBox(height: 6),
                    Text(s.lastError!,
                        style: TextStyle(fontSize: 12, color: scheme.error)),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    s.probing
                        ? 'Trying now…'
                        : 'Attempt ${s.attempt} failed — next try in ${s.secondsLeft}s',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: s.probing ? null : s.retryNow,
                        child: const Text('Retry now'),
                      ),
                      if (custom) ...[
                        OutlinedButton(
                          onPressed: () => s.openConnectionScreen(),
                          child: const Text('Edit connection'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              s.openConnectionScreen(customOn: false),
                          child: const Text('Use project default'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
