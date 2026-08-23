import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/store.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../state/auth_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';

class StorePickerScreen extends StatefulWidget {
  const StorePickerScreen({super.key});

  @override
  State<StorePickerScreen> createState() => _StorePickerScreenState();
}

class _StorePickerScreenState extends State<StorePickerScreen> {
  late Future<List<Store>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<ApiClient>().getStores();
  }

  /// Back button only when user already has a store in this session.
  bool get _hasCurrentStore =>
      (authService.isLoggedIn && authService.hasSelectedStore) ||
      (!authService.isLoggedIn && storeConfigService.storeId != null);

  void _clearCartIfNeeded() {
    final flow = context.read<OrderFlowController>();
    if (flow.cart.isNotEmpty) flow.clearCart();
  }

  /// Proceed to this store: sets session or local config, then navigates.
  Future<void> _goToStore(Store store) async {
    if (_busy) return;
    setState(() => _busy = true);
    final hadItems = context.read<OrderFlowController>().cart.isNotEmpty;
    final api = context.read<ApiClient>();
    final langCode = Localizations.localeOf(context).languageCode;
    try {
      if (authService.isLoggedIn) {
        await authService.selectStore(api, store.id);
      }
      // Always persist name/currency locally so the profile sheet can display them.
      storeConfigService.setStore(store.id,
          name: store.label(langCode), currency: store.currency);
      if (hadItems) _clearCartIfNeeded();
      if (mounted) {
        final returnTo = ModalRoute.of(context)?.settings.arguments as String?;
        Navigator.of(context)
            .pushNamedAndRemoveUntil(returnTo ?? Routes.landing, (r) => false);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Set as local default without navigating.
  void _makeDefault(Store store, String languageCode, AppLocalizations l10n) {
    storeConfigService.setStore(store.id,
        name: store.label(languageCode), currency: store.currency);
    setState(() {}); // refresh star icons
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${store.label(languageCode)} ${l10n.storePickerDefaultSetSuffix}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageCode = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(l10n.storePickerTitle),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        automaticallyImplyLeading: _hasCurrentStore,
      ),
      body: FutureBuilder<List<Store>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final stores = snapshot.data ?? const [];
          if (stores.isEmpty) {
            return Center(child: Text(l10n.storePickerEmpty));
          }
          return Stack(
            children: [
              ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: stores.length,
                itemBuilder: (context, i) {
                  final store = stores[i];
                  final isDefault = storeConfigService.storeId == store.id;
                  final isSessionStore = authService.isLoggedIn &&
                      authService.sessionStoreId == store.id;
                  final isCurrentStore = isDefault || isSessionStore;

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Store header row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.storefront_outlined,
                                    color: scheme.onSurfaceVariant, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  store.label(languageCode),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (isCurrentStore)
                                Icon(Icons.star_rounded,
                                    color: scheme.primary, size: 22),
                            ],
                          ),
                          const Divider(height: 20),
                          // Actions row
                          Row(
                            children: [
                              // Default indicator or Make Default
                              if (isCurrentStore)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check,
                                        size: 16, color: scheme.outline),
                                    const SizedBox(width: 4),
                                    Text(l10n.storePickerIsDefault,
                                        style: TextStyle(
                                            color: scheme.outline,
                                            fontSize: 13)),
                                  ],
                                )
                              else
                                TextButton.icon(
                                  icon: Icon(Icons.star_border_outlined,
                                      size: 16, color: scheme.primary),
                                  label: Text(l10n.storePickerMakeDefault,
                                      style: TextStyle(color: scheme.primary)),
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap),
                                  onPressed: _busy
                                      ? null
                                      : () => _makeDefault(
                                          store, languageCode, l10n),
                                ),
                              const Spacer(),
                              // Go to Store button
                              FilledButton.icon(
                                icon: const Icon(Icons.arrow_forward, size: 16),
                                label: Text(l10n.storePickerGoToStore),
                                style: FilledButton.styleFrom(
                                  backgroundColor: scheme.primary,
                                  foregroundColor: scheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                ),
                                onPressed:
                                    _busy ? null : () => _goToStore(store),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (_busy)
                const ColoredBox(
                  color: Colors.black26,
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      ),
    );
  }
}
