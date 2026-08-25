import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../state/browsing_mode_service.dart';
import '../state/order_flow_controller.dart';

enum BottomNavTab { home, orders, search, cart, categories }

class WahaBottomNav extends StatelessWidget {
  final BottomNavTab current;
  const WahaBottomNav({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<BrowsingModeService>().mode;
    final isRestricted =
        mode == BrowsingMode.kiosk || mode == BrowsingMode.shopping;
    final flow = context.watch<OrderFlowController>();
    final cartCount = flow.cart.fold<int>(0, (sum, c) => sum + c.quantity);
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final tabs = <(BottomNavTab, BottomNavigationBarItem)>[
      (
        BottomNavTab.home,
        BottomNavigationBarItem(
          icon: const Icon(Icons.home_outlined),
          activeIcon: const Icon(Icons.home),
          label: l10n.navHome,
        ),
      ),
      if (!isRestricted)
        (
          BottomNavTab.orders,
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: l10n.navOrders,
          ),
        ),
      if (!isRestricted)
        (
          BottomNavTab.search,
          BottomNavigationBarItem(
            icon: const Icon(Icons.search_outlined),
            activeIcon: const Icon(Icons.search),
            label: l10n.navSearch,
          ),
        ),
      (
        BottomNavTab.cart,
        BottomNavigationBarItem(
          icon: Badge(
            label: Text('$cartCount'),
            isLabelVisible: cartCount > 0,
            child: const Icon(Icons.shopping_cart_outlined),
          ),
          activeIcon: Badge(
            label: Text('$cartCount'),
            isLabelVisible: cartCount > 0,
            child: const Icon(Icons.shopping_cart),
          ),
          label: l10n.navCart,
        ),
      ),
      if (!isRestricted)
        (
          BottomNavTab.categories,
          BottomNavigationBarItem(
            icon: const Icon(Icons.category_outlined),
            activeIcon: const Icon(Icons.category),
            label: l10n.navCategories,
          ),
        ),
    ];

    final currentIndex =
        tabs.indexWhere((t) => t.$1 == current).clamp(0, tabs.length - 1);

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (i) {
        final tab = tabs[i].$1;
        if (tab == current) return;
        final route = switch (tab) {
          BottomNavTab.home => Routes.landing,
          BottomNavTab.orders => Routes.orders,
          BottomNavTab.search => Routes.search,
          BottomNavTab.cart => Routes.cart,
          BottomNavTab.categories => Routes.categories,
        };
        if (route == Routes.landing) {
          // Pop to root without pushing another landing on top.
          Navigator.of(context).popUntil((r) => r.isFirst);
        } else {
          // Keep landing as the bottom of the stack so back-button always
          // has somewhere to go — only remove routes above landing.
          Navigator.of(context).pushNamedAndRemoveUntil(
              route, ModalRoute.withName(Routes.landing));
        }
      },
      items: tabs.map((t) => t.$2).toList(),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: scheme.primary,
      unselectedItemColor: scheme.outline,
      backgroundColor: scheme.surface,
      elevation: 8,
    );
  }
}
