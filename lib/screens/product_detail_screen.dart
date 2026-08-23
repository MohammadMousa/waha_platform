import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/product.dart';
import '../router/app_router.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../utils/locale_name.dart';

class ProductDetailScreen extends StatelessWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = localeName(product.name, localeService.locale.languageCode);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 56,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              product.price.toStringAsFixed(2),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
            ),
            if (!product.active) ...[
              const SizedBox(height: 8),
              Text(l10n.productDetailUnavailable, style: const TextStyle(color: Colors.red)),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(l10n.productDetailAddToCart),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                onPressed: !product.active
                    ? null
                    : () {
                        context.read<OrderFlowController>().addProduct(product);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$name — ${l10n.productDetailAddToCart}')),
                        );
                        Navigator.of(context).pushNamed(Routes.cart);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
