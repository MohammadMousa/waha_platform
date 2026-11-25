import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../data/db/app_database.dart';
import '../data/sync/feeds.dart';
import '../data/sync/table_freshness.dart';
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

  Future<void> _resetStoreMethods(AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.offlineResetStoreMethodsAsk),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonOk)),
        ],
      ),
    );
    if (ok != true) return;
    if (!await _svc.resetStorePaymentMethods()) {
      showResultToast(l.pullBusy, problem: true);
      return;
    }
    await _pull(l);
  }

  /// Rows the server deleted that this device removed too (products,
  /// categories, barcodes, gallery images).
  Widget _removalsTile(AppLocalizations l) {
    final at = LocalPrefs.removalsAt;
    final problem = LocalPrefs.removalsProblem;
    final rule = _ruleLine(l, 'removals');
    if (at == null) {
      return ListTile(
        dense: true,
        title: Text(l.offlineRemovalsNever),
        subtitle: rule.isEmpty ? null : Text(rule.trim()),
      );
    }
    if (problem == 'unsupported') {
      return ListTile(
        dense: true,
        title: Text(l.offlineRemovalsUnsupported),
        subtitle: Text(l.offlineRemovalsChecked(whenText(l, at))),
      );
    }
    return ListTile(
      dense: true,
      title: Text(l.offlineRemovals(
          '${LocalPrefs.removalsLast}', '${LocalPrefs.removalsTotal}')),
      subtitle: Text(
        l.offlineRemovalsChecked(whenText(l, at)) +
            (problem.isNotEmpty ? '\n${l.offlineErrorLine(problem)}' : '') +
            rule,
      ),
    );
  }

  /// What the server set for this table (combined pull): off, or checked at
  /// most every so often. Nothing is shown when the server set nothing.
  String _ruleLine(AppLocalizations l, String feed) {
    final r = TableFreshness.fromPrefs().rule(feed);
    if (r == null) return '';
    if (!r.active) return '\n${l.offlineRuleOff}';
    if (r.ttlSeconds <= 0) return '';
    final s = r.ttlSeconds;
    final period = s % 86400 == 0
        ? '${s ~/ 86400}d'
        : s % 3600 == 0
            ? '${s ~/ 3600}h'
            : s % 60 == 0
                ? '${s ~/ 60}m'
                : '${s}s';
    return '\n${l.offlineRuleEvery(period)}';
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
                '${_state[f]?.lastError != null ? '\n${l.offlineErrorLine(_state[f]!.lastError!)}' : ''}'
                '${_ruleLine(l, f)}',
              ),
            ),
          _removalsTile(l),
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
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _svc.running ? null : () => _pull(l),
                    child:
                        Text(_svc.running ? l.offlinePulling : l.offlinePullNow),
                  ),
                  OutlinedButton(
                    onPressed:
                        _svc.running ? null : () => _resetStoreMethods(l),
                    child: Text(l.offlineResetStoreMethods),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
