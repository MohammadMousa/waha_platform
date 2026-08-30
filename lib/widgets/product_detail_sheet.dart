import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/product.dart';
import '../services/api_client.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import 'product_image.dart';
import 'quantity_stepper.dart';

class ProductDetailSheet extends StatefulWidget {
  final Product product;
  const ProductDetailSheet({super.key, required this.product});

  @override
  State<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<ProductDetailSheet> {
  late Product _product;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    // Only fetch if gallery or tags are missing (list products have empty lists)
    if (_product.imageResourceIds.isNotEmpty && _product.tags.isNotEmpty) return;
    try {
      final full = await context.read<ApiClient>().getProductDetail(_product.id);
      if (mounted) setState(() => _product = full);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final lang = localeService.locale.languageCode;
    final name = localeName(_product.name, lang);
    final description = localeName(_product.description, lang);
    final currency = context.watch<StoreConfigService>().storeCurrency;
    final flow = context.watch<OrderFlowController>();
    final qty = flow.cart
        .where((c) => c.productId == _product.id)
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
                      // Avatar
                      ProductImage(
                        imageResourceId: _product.imageResourceId,
                        width: double.infinity,
                        height: 200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      // Gallery strip (only when extra images exist)
                      if (_product.imageResourceIds.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _product.imageResourceIds.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) => ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ProductImage(
                                imageResourceId: _product.imageResourceIds[i],
                                width: 72,
                                height: 72,
                              ),
                            ),
                          ),
                        ),
                      ],
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
                        _product.active
                            ? _formatPrice(_product.price, currency)
                            : l10n.productDetailUnavailable,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              color: _product.active
                                  ? scheme.primary
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      // Description
                      const SizedBox(height: 16),
                      Text(
                        description.isEmpty ? '—' : description,
                        style: TextStyle(
                          color: description.isEmpty
                              ? scheme.outlineVariant
                              : scheme.onSurface.withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                      ),
                      // Tags
                      if (_product.tags.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _product.tags
                              .map((t) => Chip(
                                    label: Text(t,
                                        style: const TextStyle(fontSize: 12)),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              // Bottom: qty spinner or Add to Cart
              Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 8, 24, MediaQuery.of(context).padding.bottom + 16),
                child: _product.active
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
                                flow.addProduct(_product);
                              },
                            ),
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: QuantityStepper(
                              qty: qty,
                              onAdd: () => flow.addProduct(_product),
                              onRemove: () =>
                                  flow.updateQuantity(_product.id, qty - 1),
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
