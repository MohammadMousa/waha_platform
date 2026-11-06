import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/orders/order_push_service.dart';
import '../data/sync/sync_service.dart';

/// Settings section for orders made on the device: how many wait to be sent,
/// the failed ones (dead-letter list) with a Retry button, and a warning when
/// sending is stopped because the session was refused.
class OfflineOrdersPanel extends StatefulWidget {
  const OfflineOrdersPanel({super.key});

  @override
  State<OfflineOrdersPanel> createState() => _OfflineOrdersPanelState();
}

class _OfflineOrdersPanelState extends State<OfflineOrdersPanel> {
  final _push = OrderPushService.instance;
  OrderCounts _counts = const OrderCounts(0, 0, null);
  List<LocalOrder> _dead = [];

  @override
  void initState() {
    super.initState();
    _push.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _push.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final counts = await orderCounts(SyncService.instance.db);
    final dead = await _push.deadOrders();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _dead = dead;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.outbox_outlined),
        title: Text('Orders to send (${_counts.pending} waiting, ${_counts.dead} failed)'),
        children: [
          if (_push.authBlocked)
            const ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: Colors.orange),
              title: Text('Sending is stopped: the server refused this device\'s session.'),
              subtitle: Text('The orders are kept and will be sent once the device is signed in again.'),
            ),
          ListTile(
            dense: true,
            title: Text('Last accepted by the server: ${_counts.lastPushAt ?? '-'}'),
          ),
          if (_dead.isEmpty)
            const ListTile(dense: true, title: Text('No failed orders.'))
          else
            for (final o in _dead)
              ListTile(
                dense: true,
                title: Text('${o.orderReference}   total ${o.totalAmount} ${o.currency}'),
                subtitle: Text('${o.lastErrorCode ?? ''} ${o.lastError ?? ''}\nmade ${o.createdAt}'),
                isThreeLine: true,
                trailing: TextButton(
                  onPressed: () => _push.retryDead(o.orderId),
                  child: const Text('Retry'),
                ),
              ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: _push.running ? null : () => _push.pushPending(),
                child: Text(_push.running ? 'Sending…' : 'Send now'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
