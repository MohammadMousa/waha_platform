import 'package:flutter/material.dart';

/// Sticky checkout CTA: total on the left, a large unmistakable action on
/// the right, elevated card treatment so it reads as the primary action
/// on the screen rather than one more button in a column.
class CheckoutBar extends StatelessWidget {
  final double? total;
  final String? currency;
  final bool enabled;
  final VoidCallback onCheckout;
  final String totalLabel;
  final String checkoutLabel;

  const CheckoutBar({
    super.key,
    required this.total,
    this.currency,
    required this.enabled,
    required this.onCheckout,
    required this.totalLabel,
    required this.checkoutLabel,
  });

  String _fmt(double amount) {
    final s = amount.toStringAsFixed(2);
    if (currency == null) return s;
    final u = currency!.toUpperCase();
    if (u == 'SAR') return '$s ﷼';
    if (u == 'USD') return '\$$s';
    if (u == 'EUR') return '€$s';
    return '$s $currency';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    totalLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  Text(
                    total != null ? _fmt(total!) : '—',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: enabled ? onCheckout : null,
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                checkoutLabel,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
