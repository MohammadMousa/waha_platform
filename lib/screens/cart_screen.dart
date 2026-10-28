import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/quote.dart';
import '../router/app_router.dart';
import '../services/local_prefs.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/simulator_service.dart';
import '../state/store_config_service.dart';
import '../utils/money.dart';
import '../widgets/cart_line_tile.dart';
import '../widgets/device_pin_dialog.dart';
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

  // Secret 10-tap gesture, two different outcomes depending on the build:
  //  - Simulator-enabled (dev) builds: reveals the simulator dev-tools
  //    cluster, unchanged from before.
  //  - Production builds running Kiosk mode's own device account: there is
  //    no simulator to reveal, but Settings is otherwise completely
  //    unreachable in Kiosk mode (see kioskAllowlist) — gate a way in
  //    behind the device's own PIN instead of leaving it locked out
  //    entirely. Not offered in Shopping mode (customer's own phone).
  void _onBodyTap() {
    if (AppConfig.simulatorAvailable) {
      _tapTimer?.cancel();
      _tapCount++;
      if (_tapCount >= 10) {
        _tapCount = 0;
        context.read<SimulatorService>().showDevTools();
      } else {
        _tapTimer = Timer(const Duration(seconds: 3), () => _tapCount = 0);
      }
      return;
    }

    _tapTimer?.cancel();
    _tapCount++;
    if (_tapCount >= 10) {
      _tapCount = 0;
      _showDevicePinDialog();
    } else {
      _tapTimer = Timer(const Duration(seconds: 3), () => _tapCount = 0);
    }
  }

  Future<void> _showDevicePinDialog() async {
    final unlocked = await showDialog<bool>(
      context: context,
      builder: (_) => const DevicePinDialog(),
    );
    if (unlocked == true && mounted) {
      Navigator.of(context).pushNamed(Routes.settings);
    }
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
    final quote = flow.quote;
    final l10n = AppLocalizations.of(context)!;
    final currency = context.watch<StoreConfigService>().storeCurrency
        ?? flow.order?.currency;

    // Hidden by default — the polished design has nothing below the summary
    // card and action buttons. Settings can opt back in.
    final showBottomNav = LocalPrefs.showCartMenuInKiosk;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cartTitle),
        actions: [
          // The Cancel button on the summary card now covers "empty the
          // cart" — a second, separate clear-cart action here was
          // redundant. A language toggle is more useful in this slot.
          IconButton(
            icon: const Icon(Icons.language_outlined),
            tooltip: l10n.settingsLanguage,
            onPressed: () {
              final next = localeService.locale.languageCode == 'en'
                  ? const Locale('ar')
                  : const Locale('en');
              localeService.setLocale(next);
            },
          ),
        ],
      ),
      bottomNavigationBar:
          showBottomNav ? const WahaBottomNav(current: BottomNavTab.cart) : null,
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
                            icon: const Icon(Icons.home_outlined),
                            label: Text(l10n.ctaContinueShopping),
                            onPressed: () =>
                                goHomeKeepingLanding(Navigator.of(context)),
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
          _CartSummaryCard(
            subtotal: quote?.subtotal ?? 0.0,
            tax: quote?.tax ?? 0.0,
            total: quote?.total ?? 0.0,
            discount: quote?.discountAmount ?? 0.0,
            currency: currency,
            l10n: l10n,
            // A cart the offers bring down to nothing due is not an order.
            zeroDue: quote != null && flow.cart.isNotEmpty && quote.total <= 0,
            canCheckout: flow.cart.isNotEmpty &&
                !flow.busy &&
                !(quote != null && quote.total <= 0),
            onCancel: () {
              context.read<OrderFlowController>().clearCart();
              goHomeKeepingLanding(Navigator.of(context));
            },
            onCheckout: () => Navigator.of(context).pushNamed(Routes.checkout),
          ),
        ],
        ),
      ),
    );
  }
}

// ── Summary card — collapsed shows only the grand total; subtotal/tax only
// show once expanded. Always rendered (even on an empty cart, as 0.00) so
// the layout never jumps between empty and non-empty states. ──────────────

class _CartSummaryCard extends StatefulWidget {
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String? currency;
  final AppLocalizations l10n;
  final bool canCheckout;
  final bool zeroDue;
  final VoidCallback onCancel;
  final VoidCallback onCheckout;

  const _CartSummaryCard({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.currency,
    required this.l10n,
    required this.canCheckout,
    required this.zeroDue,
    required this.onCancel,
    required this.onCheckout,
  });

  @override
  State<_CartSummaryCard> createState() => _CartSummaryCardState();
}

class _CartSummaryCardState extends State<_CartSummaryCard> {
  bool _expanded = false;

  // Wide/landscape screens: the card stops growing past this and centers
  // instead, so the header and buttons don't stretch edge-to-edge forever.
  static const _maxWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = widget.l10n;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Text(
                          l10n.cartTotal,
                          style: TextStyle(color: scheme.outline, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          _fmt(widget.total, widget.currency),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: scheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      children: [
                        if (widget.discount > 0) ...[
                          _SummaryRow(
                            l10n.cartDiscount,
                            -widget.discount,
                            currency: widget.currency,
                          ),
                          const SizedBox(height: 4),
                        ],
                        _SummaryRow(l10n.cartSubtotal, widget.subtotal, currency: widget.currency),
                        const SizedBox(height: 4),
                        _SummaryRow(l10n.cartTax, widget.tax, currency: widget.currency),
                      ],
                    ),
                  ),
                ],
                if (widget.zeroDue)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      l10n.cartZeroDueHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: scheme.error, fontWeight: FontWeight.w600),
                    ),
                  ),
                const Divider(height: 1),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: scheme.error,
                            side: BorderSide.none,
                            shape: const RoundedRectangleBorder(),
                          ),
                          onPressed: widget.onCancel,
                          child: Text(
                            l10n.commonCancel,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            disabledBackgroundColor: Colors.green.shade600.withValues(alpha: 0.4),
                            shape: const RoundedRectangleBorder(),
                          ),
                          onPressed: widget.canCheckout ? widget.onCheckout : null,
                          child: Text(
                            l10n.checkoutButton,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        Text(_fmt(value, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

String _fmt(double amount, String? currency) => formatMoney(amount, currency);
