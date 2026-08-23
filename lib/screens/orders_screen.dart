import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/order.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/store_config_service.dart';
import '../widgets/waha_bottom_nav.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _scrollController = ScrollController();
  List<WahaOrder> _orders = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  static const _pageSize = 10;
  String? _error;
  int? _lastStoreId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload whenever the active store changes (Rule §14: store switch resets store-scoped state).
    final storeId = context.watch<StoreConfigService>().storeId
        ?? authService.sessionStoreId;
    if (storeId != _lastStoreId) {
      _lastStoreId = storeId;
      if (authService.isLoggedIn) _loadOrders();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100 &&
        !_loadingMore &&
        _hasMore &&
        !_loading) {
      _loadMore();
    }
  }

  // Always send the current storeId so switching stores fetches that store's
  // orders regardless of what the backend session last recorded (Rule §14).
  int? get _storeId =>
      context.read<StoreConfigService>().storeId ?? authService.sessionStoreId;

  Future<void> _loadOrders() async {
    final token = authService.token;
    if (token == null) return;
    final storeId = _storeId;
    setState(() {
      _loading = true;
      _error = null;
      _page = 0;
      _hasMore = true;
      _orders = [];
    });
    try {
      final orders = await context
          .read<ApiClient>()
          .getOrderHistory(token, storeId: storeId, page: 0, size: _pageSize);
      if (mounted) {
        setState(() {
          _orders = orders;
          _hasMore = orders.length == _pageSize;
          _page = 1;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load orders.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final token = authService.token;
    if (token == null) return;
    final storeId = _storeId;
    setState(() => _loadingMore = true);
    try {
      final more = await context
          .read<ApiClient>()
          .getOrderHistory(token, storeId: storeId, page: _page, size: _pageSize);
      if (mounted) {
        setState(() {
          _orders.addAll(more);
          _hasMore = more.length == _pageSize;
          _page++;
        });
      }
    } catch (_) {
      // Non-fatal — user can scroll up/down to retry
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _cancelOrder(String orderId) async {
    final token = authService.token;
    if (token == null) return;
    try {
      await context.read<ApiClient>().cancelOrder(token, orderId);
      await _loadOrders();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not cancel order.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final loggedIn = authService.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ordersTitle),
        actions: [
          if (loggedIn && !_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadOrders,
              tooltip: 'Refresh',
            ),
        ],
      ),
      bottomNavigationBar: const WahaBottomNav(current: BottomNavTab.orders),
      body: !loggedIn
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 72, color: scheme.outline),
                    const SizedBox(height: 16),
                    Text(l10n.ordersLoginPrompt,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.outline)),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed(Routes.login),
                      child: Text(l10n.profileLogin),
                    ),
                  ],
                ),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: _loadOrders,
                              child: Text(l10n.browseRetry)),
                        ],
                      ),
                    )
                  : _orders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 72, color: scheme.outline),
                              const SizedBox(height: 16),
                              Text(l10n.ordersEmpty,
                                  style: TextStyle(color: scheme.outline)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _orders.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            if (i == _orders.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                    child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )),
                              );
                            }
                            final order = _orders[i];
                            return _OrderTile(
                              order: order,
                              onTap: () => Navigator.of(context).pushNamed(
                                Routes.invoice,
                                arguments: order.orderId,
                              ),
                              onCancel: order.status == 'CREATED'
                                  ? () => _cancelOrder(order.orderId)
                                  : null,
                            );
                          },
                        ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final WahaOrder order;
  final VoidCallback onTap;
  final VoidCallback? onCancel;

  const _OrderTile({
    required this.order,
    required this.onTap,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final (Color bgColor, Color iconColor, IconData icon, String statusLabel) =
        switch (order.status) {
      'PAID' => (
          Colors.green.shade100,
          Colors.green.shade700,
          Icons.check_circle_outline,
          l10n.invoicePaid,
        ),
      'PENDING' => (
          Colors.orange.shade100,
          Colors.orange.shade700,
          Icons.hourglass_empty_outlined,
          l10n.invoicePending,
        ),
      'CANCELLED' => (
          scheme.surfaceVariant,
          scheme.outline,
          Icons.cancel_outlined,
          l10n.invoiceCancelled,
        ),
      _ => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.receipt_outlined,
          l10n.invoiceUnpaid,
        ),
    };

    return Card(
      elevation: 0,
      color: scheme.surfaceVariant.withOpacity(0.5),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: bgColor,
          child: Icon(icon, size: 18, color: iconColor),
        ),
        title: Text(
          order.displayId != null
              ? '${l10n.invoiceOrderNum} #${order.displayId}'
              : order.orderId.substring(0, 8),
        ),
        subtitle: Text(
          '${order.total.toStringAsFixed(2)} ${order.currency ?? ''}'
          ' · $statusLabel',
          style: TextStyle(
            color: order.status == 'CANCELLED' ? scheme.outline : null,
          ),
        ),
        trailing: onCancel != null
            ? TextButton(
                onPressed: onCancel,
                child: Text('Cancel',
                    style: TextStyle(color: scheme.error)),
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}
