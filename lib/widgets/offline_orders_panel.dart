import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/orders/order_push_service.dart';
import '../data/sync/sync_service.dart';
import '../l10n/generated/app_localizations.dart';
import 'run_result_text.dart';

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

  Future<void> _send(AppLocalizations l) async {
    showResultToast(l.ordersSending);
    final r = await _push.pushPending();
    showResultToast(sendResultText(l, r), problem: isProblem(r));
  }

  Future<void> _retry(AppLocalizations l, String orderId) async {
    await _push.retryDead(orderId);
    await _send(l);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final last = _push.lastResult;
    final lastAt = _push.lastResultAt;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.outbox_outlined),
        title: Text(
            l.ordersTitle('${_counts.pending}', '${_counts.dead}')),
        children: [
          if (_push.authBlocked)
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange),
              title: Text(l.ordersAuthStopped),
              subtitle: Text(l.ordersAuthStoppedHint),
            ),
          ListTile(
            dense: true,
            title: Text(l.ordersLastAccepted('${_counts.lastPushAt ?? '-'}')),
          ),
          if (last != null && lastAt != null)
            ListTile(
              dense: true,
              leading: Icon(
                isProblem(last)
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: isProblem(last) ? Colors.red.shade700 : Colors.green,
              ),
              title: Text(l.offlineLastResult(
                  clockTime(lastAt), sendResultText(l, last))),
            ),
          if (_dead.isEmpty)
            ListTile(dense: true, title: Text(l.ordersNoFailed))
          else
            for (final o in _dead)
              ListTile(
                dense: true,
                title: Text(l.ordersTotal(
                    o.orderReference, '${o.totalAmount}', o.currency)),
                subtitle: Text(
                    '${o.lastErrorCode ?? ''} ${o.lastError ?? ''}\n${l.ordersMade(o.createdAt)}'),
                isThreeLine: true,
                trailing: TextButton(
                  onPressed: _push.running ? null : () => _retry(l, o.orderId),
                  child: Text(l.ordersRetry),
                ),
              ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: _push.running ? null : () => _send(l),
                child: Text(_push.running ? l.ordersSending : l.ordersSendNow),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
