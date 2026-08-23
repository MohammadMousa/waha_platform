import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';

/// Shows session info for logged-in users.
/// Not in the Kiosk/Shopping allowlist.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    final api = context.read<ApiClient>();
    await authService.logout(api);
    // Restore anonymous session: resolve a default store in background so
    // the app keeps working (browse, scan) without requiring a fresh login.
    // Fire-and-forget — navigation happens immediately below.
    authService.resolveDefaultStore(api);
    if (mounted) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(Routes.landing, (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final loggedIn = authService.isLoggedIn;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.person_outline, size: 72, color: scheme.outline),
            const SizedBox(height: 16),
            if (loggedIn) ...[
              Text(
                '${l10n.profileLoggedInPrefix} ${authService.username}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                authService.hasSelectedStore
                    ? 'Store #${authService.sessionStoreId}'
                    : l10n.profileNoStoreSelected,
                style: TextStyle(color: scheme.outline),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(Routes.storePicker),
                child: Text(l10n.profileChangeStore),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(l10n.navOrders),
                onPressed: () =>
                    Navigator.of(context).pushNamed(Routes.orders),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _loggingOut ? null : _logout,
                child: _loggingOut
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.profileLogout),
              ),
            ] else ...[
              Text(
                l10n.profileGuestMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(Routes.login),
                child: Text(l10n.profileLogin),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
