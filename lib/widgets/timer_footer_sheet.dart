import 'package:flutter/material.dart';

/// Shared visual language for the kiosk's two countdown UIs — the idle
/// "are you still there?" warning and the paid-invoice auto-close timer.
/// A light card anchored to the bottom of the screen (rounded top corners,
/// a message, a circular countdown badge, two actions either side of it) —
/// replacing the old centered AlertDialog / plain button-row styles.
///
/// [primary] is the emphasized (filled) action nearest the countdown circle
/// on its "reading-first" side — which one that semantically is differs per
/// caller (idle: Continue; paid: New Order) — [secondary] is the outlined,
/// less emphasized one. Children are ordered [primary, circle, secondary]
/// so RTL/LTR mirroring puts primary on the natural "read first" side in
/// both directions without any manual direction checks.
class TimerFooterSheet extends StatelessWidget {
  final String? title;
  final String message;
  final int secondsLeft;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final Color primaryColor;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  const TimerFooterSheet({
    super.key,
    this.title,
    required this.message,
    required this.secondsLeft,
    required this.primaryLabel,
    required this.onPrimary,
    required this.primaryColor,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onPrimary,
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape:
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(primaryLabel, textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor.withValues(alpha: 0.12),
                      border: Border.all(color: primaryColor, width: 2),
                    ),
                    child: Text(
                      '$secondsLeft',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSecondary,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape:
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(secondaryLabel, textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
