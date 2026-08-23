import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/product.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import '../utils/scan_actions.dart';
import '../widgets/product_detail_sheet.dart';
import '../widgets/product_image.dart';
import '../widgets/scan_capture_field.dart';
import '../widgets/waha_app_bar.dart';
import '../widgets/waha_bottom_nav.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<BrowsingModeService>().mode;
    if (mode == BrowsingMode.normal) return const _NormalLanding();
    return const _ScanLanding();
  }
}

// ── Normal mode: home page ────────────────────────────────────────────────────

class _NormalLanding extends StatefulWidget {
  const _NormalLanding();

  @override
  State<_NormalLanding> createState() => _NormalLandingState();
}

class _NormalLandingState extends State<_NormalLanding> {
  List<Product>? _recentProducts;
  bool _loadingRecent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRecent());
  }

  Future<void> _loadRecent() async {
    final storeId = storeConfigService.storeId;
    if (storeId == null) return;
    if (!mounted) return;
    setState(() => _loadingRecent = true);
    try {
      final page = await context
          .read<ApiClient>()
          .getProducts(storeId: storeId, page: 0, size: 8, sort: 'createdAt,desc');
      if (mounted) setState(() => _recentProducts = page.products);
    } catch (_) {
      // Non-fatal — section just stays empty
    } finally {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final flow = context.watch<OrderFlowController>();
    final hasCart = flow.cart.isNotEmpty;
    final total = flow.quote?.total;
    final storeConfig = context.watch<StoreConfigService>();
    final currency = storeConfig.storeCurrency ?? flow.order?.currency;
    final lang = localeService.locale.languageCode;
    final _appNameStr = storeConfig.appName != null
        ? localeName(storeConfig.appName!, lang)
        : '';
    final appTitle = _appNameStr.isNotEmpty ? _appNameStr : l10n.appTitle;

    return Scaffold(
      appBar: WahaAppBar(title: appTitle),
      bottomNavigationBar: const WahaBottomNav(current: BottomNavTab.home),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Search bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: GestureDetector(
                    onTap: () =>
                        Navigator.of(context).pushNamed(Routes.search),
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: scheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: scheme.outline),
                          const SizedBox(width: 12),
                          Text(
                            l10n.homeSearchHint,
                            style:
                                TextStyle(color: scheme.outline, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Quick actions: Browse + Categories only
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.grid_view_rounded,
                          label: l10n.navBrowse,
                          onTap: () =>
                              Navigator.of(context).pushNamed(Routes.browse),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.category_outlined,
                          label: l10n.navCategories,
                          onTap: () => Navigator.of(context)
                              .pushNamed(Routes.categories),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Recently Added section header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.recentlyAdded,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed(Routes.browse),
                        child: Text(l10n.seeAll),
                      ),
                    ],
                  ),
                ),
              ),

              // Recently Added grid
              if (_loadingRecent)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                )
              else if (_recentProducts == null || _recentProducts!.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        l10n.browseEmpty,
                        style: TextStyle(color: scheme.outline),
                      ),
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final product in _recentProducts!)
                          SizedBox(
                            width: 145,
                            child: _RecentProductCard(
                              product: product,
                              currency: currency,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // Bottom padding so content clears the View Cart bar
              SliverToBoxAdapter(
                child: SizedBox(height: hasCart ? 80 : 16),
              ),
            ],
          ),

          // View Cart bar — pinned at bottom
          if (hasCart)
            Positioned(
              bottom: 0,
              left: 16,
              right: 16,
              child: _ViewCartBar(total: total, currency: currency),
            ),
        ],
      ),
    );
  }
}

class _RecentProductCard extends StatelessWidget {
  final Product product;
  final String? currency;

  const _RecentProductCard({required this.product, this.currency});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lang = Localizations.localeOf(context).languageCode;
    final name = (product.name[lang] ?? product.name['en'] ?? '').toString();

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ProductDetailSheet(product: product),
      ),
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: scheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image
            ProductImage(
              imageResourceId: product.imageResourceId,
              height: 100,
              width: double.infinity,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                _formatPrice(product.price, currency),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewCartBar extends StatelessWidget {
  final double? total;
  final String? currency;
  const _ViewCartBar({this.total, this.currency});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = total != null
        ? _formatPrice(total!, currency)
        : l10n.viewCart;

    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(Routes.cart),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF00695C),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Icon(Icons.shopping_cart_outlined, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              l10n.viewCart,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: scheme.primary, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kiosk / Shopping mode: scan-first landing ─────────────────────────────────

class _ScanLanding extends StatelessWidget {
  const _ScanLanding();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mode = context.watch<BrowsingModeService>().mode;
    final isShopping = mode == BrowsingMode.shopping;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: WahaAppBar(title: l10n.appTitle),
      bottomNavigationBar: const WahaBottomNav(current: BottomNavTab.home),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primaryContainer,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withOpacity(0.2),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(Icons.qr_code_scanner,
                        size: 68, color: scheme.primary),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    l10n.landingHeadline,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.landingSubtitle,
                    style: TextStyle(color: scheme.outline),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        if (isShopping) {
                          openCameraAndAddToCart(context);
                        } else {
                          Navigator.of(context).pushNamed(Routes.browse);
                        }
                      },
                      child: Text(
                        isShopping ? l10n.ctaStartScanning : l10n.navBrowse,
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (mode == BrowsingMode.kiosk) const ScanCaptureField(visible: false),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatPrice(double amount, String? currency) {
  final formatted = amount.toStringAsFixed(2);
  if (currency == null) return formatted;
  final upper = currency.toUpperCase();
  if (upper == 'SAR') return '$formatted ﷼';
  if (upper == 'USD') return '\$$formatted';
  if (upper == 'EUR') return '€$formatted';
  return '$formatted $currency';
}
