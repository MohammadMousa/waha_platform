import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/product.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import 'product_image.dart';
import 'quantity_stepper.dart';

class ProductDetailSheet extends StatelessWidget {
  final Product product;
  const ProductDetailSheet({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final lang = localeService.locale.languageCode;
    final name = localeName(product.name, lang);
    final description = localeName(product.description, lang);
    final currency = context.watch<StoreConfigService>().storeCurrency;
    final flow = context.watch<OrderFlowController>();
    final qty = flow.cart
        .where((c) => c.productId == product.id)
        .fold(0, (s, c) => s + c.quantity);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Close button
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product image
                      ProductImage(
                        imageResourceId: product.imageResourceId,
                        width: double.infinity,
                        height: 200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      const SizedBox(height: 20),
                      // Name
                      Text(
                        name,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      // Price
                      Text(
                        product.active
                            ? _formatPrice(product.price, currency)
                            : l10n.productDetailUnavailable,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              color: product.active
                                  ? scheme.primary
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      // Description — always shown (empty placeholder keeps space)
                      const SizedBox(height: 16),
                      Text(
                        description.isEmpty ? '—' : description,
                        style: TextStyle(
                          color: description.isEmpty
                              ? scheme.outlineVariant
                              : scheme.onSurface.withOpacity(0.7),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              // Bottom: qty spinner or Add to Cart
              Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 8, 24, MediaQuery.of(context).padding.bottom + 16),
                child: product.active
                    ? (qty == 0
                        ? SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: const Icon(Icons.add_shopping_cart),
                              label: Text(
                                l10n.productDetailAddToCart,
                                style: const TextStyle(fontSize: 16),
                              ),
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: () {
                                flow.addProduct(product);
                                // Don't close — let user adjust qty
                              },
                            ),
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: QuantityStepper(
                              qty: qty,
                              onAdd: () => flow.addProduct(product),
                              onRemove: () =>
                                  flow.updateQuantity(product.id, qty - 1),
                              size: 52,
                              fullWidth: true,
                            ),
                          ))
                    : SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(l10n.productDetailUnavailable),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}


String _formatPrice(double amount, String? currency) {
  final s = amount.toStringAsFixed(2);
  if (currency == null) return s;
  final u = currency.toUpperCase();
  if (u == 'SAR') return '$s ﷼';
  if (u == 'USD') return '\$$s';
  if (u == 'EUR') return '€$s';
  return '$s $currency';
}
