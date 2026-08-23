import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/locale_service.dart';
import '../state/store_config_service.dart';

/// Profile bottom sheet — shown from the AppBar profile icon in Normal mode.
/// Contains: session info, language switcher, store/orders/logout actions.
class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key});

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    final api = context.read<ApiClient>();
    await authService.logout(api);
    authService.resolveDefaultStore(api); // fire-and-forget
    if (mounted) {
      Navigator.of(context).pop(); // close sheet
      Navigator.of(context)
          .pushNamedAndRemoveUntil(Routes.landing, (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final loggedIn = authService.isLoggedIn;
    final storeName = context.watch<StoreConfigService>().storeName;
    final storeId = authService.hasSelectedStore
        ? authService.sessionStoreId
        : context.watch<StoreConfigService>().storeId;
    final storeLabel = storeName ??
        (storeId != null ? 'Store #$storeId' : l10n.profileNoStoreSelected);

    final currentLocale = context.watch<LocaleService>().locale;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Avatar
            CircleAvatar(
              radius: 32,
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                loggedIn ? Icons.person_rounded : Icons.person_outline,
                size: 36,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),

            // Name / guest label
            if (loggedIn) ...[
              Text(
                authService.username ?? '',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                storeLabel,
                style: TextStyle(color: scheme.outline, fontSize: 13),
              ),
            ] else
              Text(
                l10n.profileGuestMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline),
              ),

            const SizedBox(height: 20),

            // Language switcher
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.language_outlined, size: 18, color: scheme.outline),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('EN')),
                    ButtonSegment(value: 'ar', label: Text('AR')),
                  ],
                  selected: {currentLocale.languageCode},
                  onSelectionChanged: (sel) {
                    localeService.setLocale(Locale(sel.first));
                  },
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),

            if (loggedIn) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.storefront_outlined, color: scheme.primary),
                title: Text(l10n.profileChangeStore),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed(Routes.storePicker);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.receipt_long_outlined, color: scheme.primary),
                title: Text(l10n.navOrders),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed(Routes.orders);
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _loggingOut ? null : _logout,
                  child: _loggingOut
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.profileLogout),
                ),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.storefront_outlined, color: scheme.primary),
                title: Text(storeLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed(Routes.storePicker);
                },
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed(Routes.login);
                  },
                  child: Text(l10n.profileLogin),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
