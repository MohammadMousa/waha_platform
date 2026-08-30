import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/store.dart';
import '../widgets/product_image.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../services/local_prefs.dart';
import '../state/auth_service.dart';
import '../state/edit_mode_service.dart';
import '../state/order_flow_controller.dart';
import '../state/permission_service.dart';
import '../state/store_config_service.dart';
import '../widgets/edit_mode_toggle.dart';

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
    _future = _buildFuture();
  }

  Future<List<Store>> _buildFuture() {
    final api = context.read<ApiClient>();
    final token = authService.token;
    return (permissionService.can('MANAGE_STORES') && token != null)
        ? api.getAdminStores(token)
        : api.getStores();
  }

  void _reload() {
    final f = _buildFuture();
    setState(() { _future = f; });
  }

  bool get _hasCurrentStore =>
      (authService.isLoggedIn && authService.hasSelectedStore) ||
      (!authService.isLoggedIn && storeConfigService.storeId != null);

  void _clearCartIfNeeded() {
    final flow = context.read<OrderFlowController>();
    if (flow.cart.isNotEmpty) flow.clearCart();
  }

  /// Switches to a different store — updates session + in-memory config, then
  /// navigates home. Never writes to LocalPrefs (default stays unchanged).
  Future<void> _goToStore(Store store, String languageCode) async {
    if (_busy) return;
    setState(() => _busy = true);
    final hadItems = context.read<OrderFlowController>().cart.isNotEmpty;
    final api = context.read<ApiClient>();
    try {
      if (authService.isLoggedIn) {
        await authService.selectStore(api, store.id);
      }
      storeConfigService.applySessionStore(store.id,
          displayName: store.displayName?.cast<String, dynamic>(),
          slug: store.name,
          currency: store.currency);
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

  /// Refreshes the current store — re-applies session + in-memory config
  /// without navigating away. Useful for picking up new products/roles.
  Future<void> _refreshStore(
      Store store, String languageCode, AppLocalizations l10n) async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = context.read<ApiClient>();
    try {
      if (authService.isLoggedIn) {
        await authService.selectStore(api, store.id);
      }
      storeConfigService.applySessionStore(store.id,
          displayName: store.displayName?.cast<String, dynamic>(),
          slug: store.name,
          currency: store.currency);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.storePickerRefreshed),
            behavior: SnackBarBehavior.floating,
          ),
        );
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

  /// Persists the selected store as the local default. Does NOT change the
  /// active session store or navigate anywhere.
  Future<void> _makeDefault(
      Store store, String languageCode, AppLocalizations l10n) async {
    await LocalPrefs.setStoreId(store.id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${store.label(languageCode)} ${l10n.storePickerDefaultSetSuffix}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createStore() async {
    final nameCtrl = TextEditingController();
    final nameArCtrl = TextEditingController();
    final nameEnCtrl = TextEditingController();
    final currencyCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Store'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Slug (e.g. my-store)',
                  helperText: 'URL-safe identifier, letters/digits/hyphens only',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameArCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'Display Name – Arabic',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameEnCtrl,
                decoration: const InputDecoration(
                  labelText: 'Display Name – English',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: currencyCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Currency (e.g. SAR)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final token = authService.token;
    if (token == null) return;

    final slug = nameCtrl.text.trim();
    if (slug.isEmpty) return;

    final api = context.read<ApiClient>();

    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'name': slug,
        'displayName': {'ar': nameArCtrl.text.trim(), 'en': nameEnCtrl.text.trim()},
        if (currencyCtrl.text.trim().isNotEmpty) 'currency': currencyCtrl.text.trim().toUpperCase(),
      };
      await api.createStore(body, token: token);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create store: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageCode = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;
    final canManageStores = context.watch<PermissionService>().can('MANAGE_STORES');
    final isEditMode = context.watch<EditModeService>().isEditMode;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(l10n.storePickerTitle),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        automaticallyImplyLeading: _hasCurrentStore,
        actions: [
          if (canManageStores) const EditModeToggle(),
        ],
      ),
      floatingActionButton: (canManageStores && isEditMode)
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _createStore,
              icon: const Icon(Icons.add),
              label: const Text('New Store'),
            )
          : null,
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
                  // in-memory current store (set by applySessionStore on switch/refresh)
                  final isCurrentStore = storeConfigService.storeId == store.id;
                  // explicitly persisted local default (set by "Make Default" only)
                  final isDefault = LocalPrefs.storeId == store.id;

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
                          // Header row: icon + name + status badges
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: store.imageResourceId != null
                                    ? ProductImage(
                                        imageResourceId: store.imageResourceId,
                                        width: 44,
                                        height: 44,
                                      )
                                    : Container(
                                        width: 44,
                                        height: 44,
                                        color: scheme.surfaceContainerHighest,
                                        child: Icon(Icons.storefront_outlined,
                                            color: scheme.onSurfaceVariant,
                                            size: 22),
                                      ),
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
                                Icon(Icons.check_circle_outline_rounded,
                                    color: scheme.primary, size: 20),
                              if (isDefault) ...[
                                if (isCurrentStore) const SizedBox(width: 6),
                                Icon(Icons.star_rounded,
                                    color: Colors.amber.shade600, size: 20),
                              ],
                            ],
                          ),
                          const Divider(height: 20),
                          // Actions row
                          Row(
                            children: [
                              // Left: default status or make-default button
                              if (isDefault)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star_rounded,
                                        size: 15,
                                        color: Colors.amber.shade600),
                                    const SizedBox(width: 4),
                                    Text(l10n.storePickerIsDefault,
                                        style: TextStyle(
                                            color: Colors.amber.shade700,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
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
                              // Edit button — only in edit mode with MANAGE_STORES
                              if (isEditMode && canManageStores) ...[
                                IconButton(
                                  icon: Icon(Icons.edit_outlined,
                                      color: scheme.primary, size: 20),
                                  tooltip: 'Edit store',
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.of(context).pushNamed(
                                            Routes.storeEdit,
                                            arguments: store,
                                          ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              // Right: refresh if current, go-to if not
                              if (isCurrentStore)
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: Text(l10n.storePickerRefreshStore),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: scheme.primary,
                                    side: BorderSide(color: scheme.primary),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _refreshStore(
                                          store, languageCode, l10n),
                                )
                              else
                                FilledButton.icon(
                                  icon: const Icon(Icons.arrow_forward,
                                      size: 16),
                                  label: Text(l10n.storePickerGoToStore),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: scheme.primary,
                                    foregroundColor: scheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _goToStore(store, languageCode),
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
