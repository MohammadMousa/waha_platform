import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/store.dart';
import '../router/app_router.dart';
import '../state/browsing_mode_service.dart';
import '../state/permission_service.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';

/// Admin navigation drawer — only shown when the user has MANAGE_STORES
/// permission and the app is in Normal mode.
class WahaAdminDrawer extends StatelessWidget {
  const WahaAdminDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<BrowsingModeService>().mode;
    if (mode != BrowsingMode.normal) return const SizedBox.shrink();
    if (!permissionService.can('MANAGE_STORES')) return const SizedBox.shrink();

    final cfg = context.watch<StoreConfigService>();
    final lang = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              color: scheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.admin_panel_settings_outlined,
                      color: scheme.onPrimaryContainer, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    _storeName(cfg, lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Admin',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _Section('Store Settings'),
                  _Tile(
                    icon: Icons.store_outlined,
                    label: 'Edit Store',
                    onTap: () {
                      Navigator.pop(context);
                      final store = _buildStore(cfg);
                      if (store != null) {
                        Navigator.of(context)
                            .pushNamed(Routes.storeEdit, arguments: store);
                      }
                    },
                  ),
                  _Tile(
                    icon: Icons.payment_outlined,
                    label: 'Payment Methods',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).pushNamed(Routes.paymentMethods);
                    },
                  ),
                  _Tile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Receipt Info',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).pushNamed(Routes.receiptInfoEdit);
                    },
                  ),
                  _Tile(
                    icon: Icons.integration_instructions_outlined,
                    label: 'Odoo Integration',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).pushNamed(Routes.odooAdmin);
                    },
                  ),
                  const Divider(),
                  _Section('Catalog'),
                  _Tile(
                    icon: Icons.grid_view_outlined,
                    label: 'Products',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).pushNamed(Routes.browse);
                    },
                  ),
                  _Tile(
                    icon: Icons.category_outlined,
                    label: 'Categories',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).pushNamed(Routes.categories);
                    },
                  ),
                  const Divider(),
                  _Tile(
                    icon: Icons.folder_open_outlined,
                    label: 'Files Manager',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).pushNamed(Routes.resourceExplorer);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _storeName(StoreConfigService cfg, String lang) {
    if (cfg.storeDisplayName != null) {
      final n = localeName(cfg.storeDisplayName!, lang);
      if (n.isNotEmpty) return n;
    }
    return cfg.storeName ?? 'Store';
  }

  Store? _buildStore(StoreConfigService cfg) {
    final id = cfg.storeId;
    if (id == null) return null;
    return Store(
      id: id,
      name: cfg.storeName ?? '',
      displayName:
          cfg.storeDisplayName?.map((k, v) => MapEntry(k, v.toString())),
      currency: cfg.storeCurrency,
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
      dense: true,
    );
  }
}
