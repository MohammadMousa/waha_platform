import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/browsing_mode_service.dart';
import '../state/permission_service.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';

/// Admin navigation drawer — stub kept for compatibility.
/// Admin features have moved to the dedicated waha_admin app.
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

    final storeName = cfg.storeDisplayName != null
        ? localeName(cfg.storeDisplayName!, lang)
        : (cfg.storeName ?? 'Store');

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
              color: scheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.admin_panel_settings_outlined,
                      color: scheme.onPrimaryContainer, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    storeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use Waha Admin for management',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new_outlined,
                          size: 48, color: scheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'Admin features have moved to the Waha Admin app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
