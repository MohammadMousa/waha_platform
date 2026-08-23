import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/quote.dart';
import '../router/app_router.dart';
import '../state/browsing_mode_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
import '../utils/scan_actions.dart';
import '../widgets/cart_line_tile.dart';
import '../widgets/checkout_bar.dart';
import '../widgets/waha_bottom_nav.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OrderFlowController>();
    final mode = context.watch<BrowsingModeService>().mode;
    final isShopping = mode == BrowsingMode.shopping;
    final quote = flow.quote;
    final l10n = AppLocalizations.of(context)!;
    final currency = context.watch<StoreConfigService>().storeCurrency
        ?? flow.order?.currency;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cartTitle),
        actions: [
          if (flow.cart.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.cartClearTitle,
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l10n.cartClearTitle),
                    content: Text(l10n.cartClearMessage),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(l10n.cartClearCancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(l10n.cartClearConfirm),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  context.read<OrderFlowController>().clearCart();
                }
              },
            ),
        ],
      ),
      bottomNavigationBar: const WahaBottomNav(current: BottomNavTab.cart),
      body: Column(
        children: [
          if (flow.lastError != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.all(12),
              child: Text(flow.lastError!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: flow.cart.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_cart_outlined,
                              size: 72, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            l10n.cartEmptyTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.cartEmptySubtitle,
                            style: TextStyle(color: Theme.of(context).colorScheme.outline),
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            icon: Icon(isShopping
                                ? Icons.qr_code_scanner
                                : Icons.home_outlined),
                            label: Text(
                              isShopping ? l10n.ctaStartScanning : l10n.ctaContinueShopping,
                            ),
                            onPressed: () {
                              if (isShopping) {
                                openCameraAndAddToCart(context);
                              } else {
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                    Routes.landing, (r) => false);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: flow.cart.length,
                    itemBuilder: (context, i) {
                      final item = flow.cart[i];
                      QuoteLine? line;
                      if (quote != null) {
                        for (final l in quote.items) {
                          if (l.productId == item.productId) {
                            line = l;
                            break;
                          }
                        }
                      }
                      final controller = context.read<OrderFlowController>();
                      return CartLineTile(
                        item: item,
                        line: line,
                        currency: currency,
                        onQuantityChanged: (q) =>
                            controller.updateQuantity(item.productId, q),
                        onRemove: () => controller.removeItem(item.productId),
                      );
                    },
                  ),
          ),
          if (quote != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  _SummaryRow(l10n.cartSubtotal, quote.subtotal, currency: currency),
                  _SummaryRow(l10n.cartTax, quote.tax, currency: currency),
                ],
              ),
            ),
          CheckoutBar(
            total: quote?.total,
            currency: currency,
            enabled: flow.cart.isNotEmpty && !flow.busy,
            onCheckout: () => Navigator.of(context).pushNamed(Routes.checkout),
            totalLabel: l10n.cartTotal,
            checkoutLabel: l10n.checkoutButton,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final String? currency;
  const _SummaryRow(this.label, this.value, {this.currency});

  @override
  Widget build(BuildContext context) {
    const style = null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_fmt(value, currency), style: style),
        ],
      ),
    );
  }
}

String _fmt(double amount, String? currency) {
  final s = amount.toStringAsFixed(2);
  if (currency == null) return s;
  final u = currency.toUpperCase();
  if (u == 'SAR') return '$s ﷼';
  if (u == 'USD') return '\$$s';
  if (u == 'EUR') return '€$s';
  return '$s $currency';
}
