import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/quote.dart';
import '../router/app_router.dart';
import '../state/browsing_mode_service.dart';
import '../state/order_flow_controller.dart';
import '../state/simulator_service.dart';
import '../state/store_config_service.dart';
import '../utils/scan_actions.dart';
import '../widgets/cart_line_tile.dart';
import '../widgets/checkout_bar.dart';
import '../widgets/waha_bottom_nav.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  // Secret dev-tools toggle: 10 taps anywhere on the cart body within 3 s.
  int _tapCount = 0;
  Timer? _tapTimer;

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  final Set<int> _flashingIds = {};
  Timer? _flashTimer;
  late final OrderFlowController _flow;

  void _onBodyTap() {
    if (!AppConfig.simulatorAvailable) return;
    _tapTimer?.cancel();
    _tapCount++;
    if (_tapCount >= 10) {
      _tapCount = 0;
      context.read<SimulatorService>().showDevTools();
      return;
    }
    _tapTimer = Timer(const Duration(seconds: 3), () => _tapCount = 0);
  }

  @override
  void initState() {
    super.initState();
    _flow = context.read<OrderFlowController>();
    _flow.addListener(_onFlowChanged);
  }

  void _onFlowChanged() {
    final flow = _flow;
    final touched = flow.lastTouchedProductId;
    if (touched == null || !mounted) return;
    flow.lastTouchedProductId = null; // consume — no notifyListeners needed

    // Flash highlight
    setState(() => _flashingIds.add(touched));
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flashingIds.clear());
    });

    // Scroll the item into view after the frame renders with the new item
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[touched];
      final ctx = key?.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.5);
      }
    });
  }

  GlobalKey _keyFor(int productId) =>
      _itemKeys.putIfAbsent(productId, GlobalKey.new);

  @override
  void dispose() {
    _flow.removeListener(_onFlowChanged);
    _scrollController.dispose();
    _tapTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _onBodyTap,
        child: Column(
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
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: flow.cart.length,
                    itemBuilder: (context, i) {
                      final item = flow.cart[i];
                      QuoteLine? line;
                      if (quote != null) {
                        for (final l in quote.items) {
                          if (l.productId == item.productId) { line = l; break; }
                        }
                      }
                      final controller = context.read<OrderFlowController>();
                      final flashing = _flashingIds.contains(item.productId);
                      return AnimatedContainer(
                        key: _keyFor(item.productId),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: flashing
                              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CartLineTile(
                          item: item,
                          line: line,
                          currency: currency,
                          onQuantityChanged: (q) =>
                              controller.updateQuantity(item.productId, q),
                          onRemove: () => controller.removeItem(item.productId),
                        ),
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
