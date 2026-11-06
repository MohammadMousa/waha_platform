import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/sync/feeds.dart';
import '../data/sync/sync_service.dart';

/// Read-only view of the local offline data for the Settings screen:
/// per feed the row count, saved cursor, last pull and whether one full pull
/// has finished. Temporary diagnostics for the offline rollout.
class OfflineDataPanel extends StatefulWidget {
  const OfflineDataPanel({super.key});

  @override
  State<OfflineDataPanel> createState() => _OfflineDataPanelState();
}

class _OfflineDataPanelState extends State<OfflineDataPanel> {
  final _svc = SyncService.instance;
  Map<String, int> _counts = {};
  Map<String, SyncStateData> _state = {};

  @override
  void initState() {
    super.initState();
    _svc.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _svc.removeListener(_load);
    super.dispose();
  }

  Future<int> _count(TableInfo t) async {
    final c = countAll();
    final q = _svc.db.selectOnly(t)..addColumns([c]);
    return (await q.getSingle()).read(c) ?? 0;
  }

  Future<void> _load() async {
    final db = _svc.db;
    final counts = <String, int>{
      'products': await _count(db.localProducts),
      'barcodes': await _count(db.localBarcodes),
      'categories': await _count(db.localCategories),
      'payment-methods': await _count(db.localPaymentMethods),
      'store-payment-methods': await _count(db.localStorePaymentMethods),
      'product-images': await _count(db.localProductImages),
    };
    final rows = await db.select(db.syncState).get();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _state = {for (final r in rows) r.feed: r};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.storage_outlined),
        title: const Text('Offline data'),
        children: [
          for (final f in kSyncFeeds)
            ListTile(
              dense: true,
              title: Text('$f: ${_counts[f] ?? 0} rows'
                  '${_state[f]?.fullPullDone == true ? ' (full pull done)' : ' (not complete)'}'),
              subtitle: Text(
                'cursor ${_state[f]?.since ?? '-'} / ${_state[f]?.afterId ?? 0}'
                '\nlast pull ${_state[f]?.lastPullAt ?? '-'}'
                '${_state[f]?.lastError != null ? '\nerror: ${_state[f]!.lastError}' : ''}',
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: _svc.running ? null : () => _svc.runOnce(),
                child: Text(_svc.running ? 'Pulling…' : 'Pull now'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
