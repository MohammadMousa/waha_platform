import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/product.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../state/auth_service.dart';
import '../state/edit_mode_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/permission_service.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import '../widgets/edit_mode_toggle.dart';
import '../widgets/product_detail_sheet.dart';
import '../widgets/product_image.dart';
import '../widgets/quantity_stepper.dart';
import '../widgets/waha_app_bar.dart';
import '../widgets/waha_bottom_nav.dart';

class BrowseScreen extends StatefulWidget {
  final int? categoryId;
  final String? browseTitle;
  /// Pre-fill a search query — uses searchProducts API instead of getProducts.
  final String? searchQuery;

  const BrowseScreen({super.key, this.categoryId, this.browseTitle, this.searchQuery});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final List<Product> _products = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  bool get _sessionResolvesStore =>
      authService.isLoggedIn && authService.hasSelectedStore;

  Future<void> _loadPage() async {
    if (!_sessionResolvesStore && storeConfigService.storeId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(
            Routes.storePicker,
            arguments: Routes.browse,
          );
        }
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final result = widget.searchQuery != null
          ? await api.searchProducts(
              q: widget.searchQuery!,
              storeId: _sessionResolvesStore ? null : storeConfigService.storeId,
              token: _sessionResolvesStore ? authService.token : null,
              page: _page,
            )
          : await api.getProducts(
              storeId: _sessionResolvesStore ? null : storeConfigService.storeId,
              token: _sessionResolvesStore ? authService.token : null,
              page: _page,
              categoryId: widget.categoryId,
            );
      setState(() {
        _products.addAll(result.products);
        _hasMore = result.hasMore;
        _page += 1;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context)!.browseLoadError);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _retry() {
    setState(() {
      _products.clear();
      _page = 0;
      _hasMore = true;
    });
    _loadPage();
  }

  void _showProductSheet(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductDetailSheet(product: product),
    );
  }

  Future<void> _refreshProduct(int productId) async {
    try {
      final updated = await context.read<ApiClient>().getProductDetail(productId);
      if (!mounted) return;
      setState(() {
        final i = _products.indexWhere((p) => p.id == productId);
        if (i >= 0) _products[i] = updated;
      });
    } catch (_) {}
  }

  void _editProduct(Product product) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Product'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context)
                    .pushNamed(Routes.productEdit, arguments: product.id)
                    .then((updated) {
                  if (updated == true) _refreshProduct(product.id);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final flow = context.watch<OrderFlowController>();
    final cartCount = flow.cart.fold<int>(0, (s, c) => s + c.quantity);
    final cartTotal = flow.quote?.total;
    final currency = context.watch<StoreConfigService>().storeCurrency ??
        flow.order?.currency;

    final canEditProducts = context.watch<PermissionService>().can('EDIT_PRODUCTS');

    return Scaffold(
      appBar: WahaAppBar(
        title: widget.browseTitle ?? widget.searchQuery ?? l10n.browseTitle,
        extraActions: [
          if (canEditProducts) const EditModeToggle(),
        ],
      ),
      bottomNavigationBar: const WahaBottomNav(current: BottomNavTab.home),
      body: Stack(
        children: [
          _buildBody(l10n, flow, canEditProducts),
          if (cartCount > 0)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _ViewCartBar(total: cartTotal, currency: currency),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, OrderFlowController flow, bool canEditProducts) {
    if (_products.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_products.isEmpty && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_outlined,
                  size: 56,
                  color:
                      Theme.of(context).colorScheme.outline.withOpacity(0.5)),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _retry, child: Text(l10n.browseRetry)),
            ],
          ),
        ),
      );
    }
    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 56,
                color:
                    Theme.of(context).colorScheme.outline.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(l10n.browseEmpty),
          ],
        ),
      );
    }

    final cartCount = flow.cart.fold<int>(0, (s, c) => s + c.quantity);

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, cartCount > 0 ? 108 : 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.68,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _products.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _products.length) {
          return Center(
            child: _loading
                ? const CircularProgressIndicator()
                : TextButton(
                    onPressed: _loadPage,
                    child: Text(l10n.browseLoadMore),
                  ),
          );
        }
        final product = _products[i];
        final cartItem =
            flow.cart.where((c) => c.productId == product.id).firstOrNull;
        final qty = cartItem?.quantity ?? 0;
        final isEditMode = context.watch<EditModeService>().isEditMode;
        return _ProductCell(
          product: product,
          qty: qty,
          onTap: () => _showProductSheet(product),
          onAdd: product.active ? () => flow.addProduct(product) : null,
          onRemoveOne: qty > 0
              ? () => flow.updateQuantity(product.id, qty - 1)
              : null,
          isEditMode: isEditMode && canEditProducts,
          onEdit: () => _editProduct(product),
        );
      },
    );
  }
}

class _ViewCartBar extends StatelessWidget {
  final double? total;
  final String? currency;
  const _ViewCartBar({required this.total, this.currency});

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
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(Routes.cart),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFF00695C),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Icon(Icons.shopping_cart_outlined,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              l10n.viewCart,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            if (total != null)
              Text(
                _fmt(total!),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }
}

class _ProductCell extends StatelessWidget {
  final Product product;
  final int qty;
  final VoidCallback onTap;
  final VoidCallback? onAdd;
  final VoidCallback? onRemoveOne;
  final bool isEditMode;
  final VoidCallback? onEdit;

  const _ProductCell({
    required this.product,
    required this.qty,
    required this.onTap,
    required this.onAdd,
    required this.onRemoveOne,
    this.isEditMode = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = localeName(product.name, localeService.locale.languageCode);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image — fills entire cell area
          Expanded(
            child: Stack(
              children: [
                ProductImage(
                  imageResourceId: product.imageResourceId,
                  width: double.infinity,
                  borderRadius: BorderRadius.circular(12),
                ),
                // Quantity control overlay — bottom-right
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: QuantityStepper(
                    qty: qty,
                    onAdd: onAdd,
                    onRemove: onRemoveOne,
                    active: onAdd != null,
                    size: 28,
                  ),
                ),
                // Edit pen — top-right, only in edit mode
                if (isEditMode)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: onEdit,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.edit_outlined,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Price
          Text(
            product.active ? product.price.toStringAsFixed(2) : '—',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: product.active ? scheme.primary : scheme.outline,
            ),
          ),
          // Name
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }
}

