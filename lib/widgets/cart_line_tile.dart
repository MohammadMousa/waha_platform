import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/cart_item.dart';
import '../models/quote.dart';
import '../state/locale_service.dart';
import '../utils/locale_name.dart';
import '../utils/money.dart';
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
    final discount = line?.discountAmount ?? 0.0;
    final hasDiscount = lineTotal != null && discount > 0;
    // Server-calculated: net = before-offer total minus the line's discount.
    final shownTotal = hasDiscount ? lineTotal - discount : lineTotal;
    final hasOffer = line?.offer != null;

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
                    localeName(item.name, localeService.locale.languageCode),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unitPrice != null
                        ? '${formatMoney(unitPrice, currency)} ${l10n.perUnit}'
                        : 'Calculating price…',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  if (hasOffer) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        l10n.cartBeforeDiscount,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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
                if (hasDiscount)
                  Text(
                    formatMoney(lineTotal, currency),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                if (shownTotal != null)
                  Text(
                    formatMoney(shownTotal, currency),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
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

