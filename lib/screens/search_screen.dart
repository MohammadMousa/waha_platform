import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/product.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import '../widgets/product_detail_sheet.dart';
import '../widgets/product_image.dart';
import '../widgets/waha_bottom_nav.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Product> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    final storeId = authService.sessionStoreId ?? storeConfigService.storeId;
    // No store context means the backend will reject with 400 — guard early
    // to give a friendlier message than a raw API error.
    if (storeId == null) {
      if (mounted) {
        setState(() {
          _error = 'No store selected. Please pick a store from your profile first.';
          _loading = false;
          _searched = true;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final page = await context.read<ApiClient>().searchProducts(
            q: q,
            storeId: storeId,
            token: authService.isLoggedIn ? authService.token : null,
          );
      if (mounted) setState(() => _results = page.products);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSheet(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductDetailSheet(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final flow = context.watch<OrderFlowController>();
    final currency = context.watch<StoreConfigService>().storeCurrency;
    final lang = localeService.locale.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchTitle)),
      bottomNavigationBar: const WahaBottomNav(current: BottomNavTab.search),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ),
          Expanded(
            child: _buildBody(l10n, scheme, flow, currency, lang),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ColorScheme scheme,
      OrderFlowController flow, String? currency, String lang) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (!_searched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: scheme.outline.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(l10n.searchHint,
                style: TextStyle(color: scheme.outline)),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_outlined,
                size: 64, color: scheme.outline.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(l10n.browseEmpty, style: TextStyle(color: scheme.outline)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.68,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final product = _results[i];
        final qty = flow.cart
            .where((c) => c.productId == product.id)
            .fold(0, (s, c) => s + c.quantity);
        final name = localeName(product.name, lang);
        final price = _fmtPrice(product.price, currency);
        return GestureDetector(
          onTap: () => _showSheet(product),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ProductImage(
                          imageResourceId: product.imageResourceId,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: qty > 0
                          ? _SearchQtyBadge(qty: qty)
                          : GestureDetector(
                              onTap: product.active
                                  ? () => flow.addProduct(product)
                                  : null,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: product.active
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.add,
                                    size: 18,
                                    color: product.active
                                        ? scheme.onPrimary
                                        : scheme.onSurface
                                            .withValues(alpha: 0.4)),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(price,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: product.active ? scheme.primary : scheme.outline)),
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, height: 1.3)),
            ],
          ),
        );
      },
    );
  }
}

class _SearchQtyBadge extends StatelessWidget {
  final int qty;
  const _SearchQtyBadge({required this.qty});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF00796B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$qty',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

String _fmtPrice(double amount, String? currency) {
  final s = amount.toStringAsFixed(2);
  if (currency == null) return s;
  final u = currency.toUpperCase();
  if (u == 'SAR') return '$s ﷼';
  if (u == 'USD') return '\$$s';
  if (u == 'EUR') return '€$s';
  return '$s $currency';
}
