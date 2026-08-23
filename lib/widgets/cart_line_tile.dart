import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/cart_item.dart';
import '../models/quote.dart';
import 'product_image.dart';
import 'quantity_stepper.dart';

/// A cart line as its own card: identity + unit price on the left, a
/// proper stepper for quantity, and the line total pulled from the last
/// quote — never computed on-device. `line` is null until the first quote
/// lands (now a background call — see OrderFlowController.scanBarcode),
/// so this renders a "calculating" placeholder rather than a blank price.
class CartLineTile extends StatelessWidget {
  final CartItem item;
  final QuoteLine? line;
  final String? currency;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  const CartLineTile({
    super.key,
    required this.item,
    required this.line,
    this.currency,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final unitPrice = line?.unitPrice;
    final lineTotal = line?.lineTotal;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ProductImage(
                imageResourceId: item.imageResourceId,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unitPrice != null
                        ? '${unitPrice.toStringAsFixed(2)}${currency != null ? ' $currency' : ''} ${l10n.perUnit}'
                        : 'Calculating price…',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 10),
                  QuantityStepper(
                    qty: item.quantity,
                    onAdd: () => onQuantityChanged(item.quantity + 1),
                    onRemove: () => onQuantityChanged(item.quantity - 1),
                    size: 30,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
                const SizedBox(height: 14),
                if (lineTotal != null)
                  RichText(
                    textAlign: TextAlign.end,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: lineTotal.toStringAsFixed(2),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (currency != null)
                          TextSpan(
                            text: ' $currency',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Text('—', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

