import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/sync/feeds.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/local_prefs.dart';
import '../utils/time_text.dart';
import 'run_result_text.dart';
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
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_load);
    _load();
    // Redraw every 30 s so the "ago" texts keep moving.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
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

  Future<void> _pull(AppLocalizations l) async {
    showResultToast(l.offlinePulling);
    final r = await _svc.runOnce(manual: true);
    showResultToast(pullResultText(l, r), problem: isProblem(r));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final last = _svc.lastResult;
    final lastAt = _svc.lastResultAt;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.storage_outlined),
        title: Text(l.offlineDataTitle),
        children: [
          for (final f in kSyncFeeds)
            ListTile(
              dense: true,
              title: Text('${l.offlineRows(f, '${_counts[f] ?? 0}')} '
                  '${_state[f]?.fullPullDone == true ? l.offlineFullDone : l.offlineNotComplete}'),
              subtitle: Text(
                '${l.offlineCursor('${_state[f]?.since ?? '-'}', '${_state[f]?.afterId ?? 0}')}'
                '\n${l.offlineLastPull(whenIsoText(l, _state[f]?.lastPullAt))}'
                '${_state[f]?.lastError != null ? '\n${l.offlineErrorLine(_state[f]!.lastError!)}' : ''}',
              ),
            ),
          ListTile(
            dense: true,
            title: Text(
                l.offlineLastAttempt(whenText(l, LocalPrefs.pullAttemptAt))),
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
                  whenText(l, lastAt), pullResultText(l, last))),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: _svc.running ? null : () => _pull(l),
                child: Text(_svc.running ? l.offlinePulling : l.offlinePullNow),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
