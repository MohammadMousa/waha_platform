import 'dart:async';

import '../db/app_database.dart';
import 'feeds.dart';
import 'removals.dart';
import 'sync_engine.dart';
import 'table_freshness.dart';

/// The server does not have the combined call (404): use the per-table way.
class CombinedNotSupported implements Exception {
  const CombinedNotSupported();
}

/// One table inside a combined answer.
class CombinedTable {
  /// `disabled`, `fresh` or `unknown` when the server did not query it.
  final String? skipped;

  /// No room in this answer; the cursor stays as sent.
  final bool deferred;
  final PullPage? page;
  const CombinedTable({this.skipped, this.deferred = false, this.page});
}

/// The removals part of a combined answer.
class CombinedRemovals {
  final String? skipped;
  final RemovalsPage? page;

  /// With `skipped: disabled` the server still hands out the newest position.
  final int? startingPosition;
  const CombinedRemovals({this.skipped, this.page, this.startingPosition});
}

/// The answer of POST /api/sync/pull.
class CombinedAnswer {
  final String? serverTime;
  final Map<String, dynamic>? deviceConfig;
  final Map<String, TableRule> tableConfig;
  final CombinedRemovals? removals;
  final Map<String, CombinedTable> tables;
  const CombinedAnswer({
    required this.serverTime,
    required this.deviceConfig,
    required this.tableConfig,
    required this.removals,
    required this.tables,
  });

  factory CombinedAnswer.parse(Map<String, dynamic> j) {
    CombinedRemovals? rem;
    final r = j['removals'];
    if (r is Map<String, dynamic>) {
      final next = r['next'] as Map<String, dynamic>?;
      final skipped = r['skipped'] as String?;
      if (skipped != null) {
        rem = CombinedRemovals(
            skipped: skipped,
            startingPosition: (next?['afterId'] as num?)?.toInt());
      } else {
        rem = CombinedRemovals(
          page: RemovalsPage(
            items: [
              for (final i in (r['items'] as List<dynamic>? ?? []))
                (
                  (i as Map<String, dynamic>)['table'] as String,
                  (i['rowId'] as num).toInt()
                ),
            ],
            last: r['last'] as bool? ?? true,
            nextAfterId: (next?['afterId'] as num?)?.toInt() ?? 0,
            resetRequired: r['resetRequired'] as bool? ?? false,
          ),
        );
      }
    }
    final tables = <String, CombinedTable>{};
    final t = j['tables'];
    if (t is Map<String, dynamic>) {
      for (final e in t.entries) {
        final m = e.value as Map<String, dynamic>;
        final skipped = m['skipped'] as String?;
        if (skipped != null) {
          tables[e.key] = CombinedTable(skipped: skipped);
        } else if (m['deferred'] == true) {
          tables[e.key] = const CombinedTable(deferred: true);
        } else {
          final next = m['next'] as Map<String, dynamic>?;
          tables[e.key] = CombinedTable(
            page: PullPage(
              items: (m['items'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>(),
              last: m['last'] as bool? ?? true,
              nextSince: next?['since'] as String?,
              nextAfterId: (next?['afterId'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
    }
    return CombinedAnswer(
      serverTime: j['serverTime'] as String?,
      deviceConfig: j['deviceConfig'] as Map<String, dynamic>?,
      tableConfig: TableFreshness.parseConfig(j['tableConfig']),
      removals: rem,
      tables: tables,
    );
  }
}

/// Sends one combined request. Must throw [PullCancelled] when [abort]
/// completes, [PullUnauthorized] on a 401, [CombinedNotSupported] on a 404.
typedef CombinedFetcher = Future<CombinedAnswer> Function(
    Map<String, dynamic> body, Future<void> abort);

/// What a combined pull did.
class CombinedResult {
  /// Rows that were new or changed (not the rows received).
  final int rows;
  final int calls;
  final int removed;

  /// True only when the server really listed removals (a deletion list came
  /// back). False when it answered `fresh` or `disabled`: nothing was checked.
  final bool removalsChecked;
  const CombinedResult(
      {required this.rows,
      required this.calls,
      required this.removed,
      this.removalsChecked = false});
}

/// The pull as ONE request (and more only while a table has more to send).
///
/// What it keeps from the per-table pull: the cursor rules (10 s overlap on
/// the first request of a table, the returned cursor afterwards, a page and
/// its cursor saved in one transaction), upsert, removals applied before the
/// tables, and "a cut or lost answer saves nothing".
class CombinedPuller {
  CombinedPuller({
    required this.db,
    required this.fetch,
    required this.freshness,
    required this.onDeviceConfig,
    this.pageSize = 200,
    this.overlap = const Duration(seconds: 10),
    this.onCall,
    this.onProgress,
  });

  final AppDatabase db;
  final CombinedFetcher fetch;
  final TableFreshness freshness;
  final Future<void> Function(Map<String, dynamic> deviceConfig) onDeviceConfig;
  final int pageSize;
  final Duration overlap;

  /// Info line per call: (call number, asked, skipped fresh/disabled, rows).
  final void Function(
      int call, List<String> asked, List<String> skipped, int rows)? onCall;
  final void Function(int done, int total, String step)? onProgress;

  /// Tables still to finish when the last run stopped (for the error note).
  List<String> unfinished = const [];

  static const _removals = 'removals';

  Future<({String? since, int afterId})?> _startCursor(String feed) async {
    final s = await (db.select(db.syncState)..where((t) => t.feed.equals(feed)))
        .getSingleOrNull();
    if (s?.since == null) return null;
    final t = DateTime.parse(s!.since!).toUtc().subtract(overlap);
    return (since: t.toIso8601String(), afterId: 0);
  }

  Future<CombinedResult> run({
    required bool manual,
    required Future<void> abort,
    Future<void> Function()? beforeEachCall,
  }) async {
    final pending = <String>[...kSyncFeeds];
    final cursor = <String, ({String? since, int afterId})?>{
      for (final f in kSyncFeeds) f: await _startCursor(f),
    };
    var removalsPosition = await Removals.savedPosition(db);
    var removalsPending = true;
    var rows = 0, removed = 0, calls = 0;
    var resetDone = false;
    var removalsChecked = false;
    final total = kSyncFeeds.length + 1;

    try {
      while (true) {
        if (beforeEachCall != null) await beforeEachCall();

        // Leave out what the saved settings say not to ask for.
        final asked = <String>[];
        final skippedHere = <String>[];
        final body = <String, dynamic>{
          'size': pageSize,
          'force': manual,
          'tables': <String, dynamic>{},
        };
        for (final f in List<String>.of(pending)) {
          if (!freshness.shouldSend(f, force: manual)) {
            pending.remove(f);
            skippedHere.add(f);
            continue;
          }
          asked.add(f);
          final c = cursor[f];
          final checked = freshness.checkedAt[f];
          (body['tables'] as Map<String, dynamic>)[f] = c == null
              ? null
              : {
                  'since': c.since,
                  'afterId': c.afterId,
                  if (checked != null) 'checkedAt': checked,
                };
        }
        // Removals are treated like a table: left out while switched off or
        // inside their period (the deletions wait on the server), and only
        // while a position is saved (with none, the server must hand out the
        // starting position, so we always ask). Once they finished in this
        // pull, later calls leave them out too.
        final askRemovals = removalsPending &&
            (removalsPosition == null ||
                freshness.shouldSend(_removals, force: manual));
        if (removalsPending && !askRemovals) {
          removalsPending = false;
          skippedHere.add(_removals);
        }
        if (askRemovals) {
          if (removalsPosition != null) {
            body['removalsAfterId'] = removalsPosition;
          }
          final rc = freshness.checkedAt[_removals];
          if (rc != null) body['removalsCheckedAt'] = rc;
        }

        if (askRemovals) asked.add(_removals);
        final answer = await fetch(body, abort);
        calls++;
        var rowsThisCall = 0;
        var moved = false;

        freshness.onAnswer(
            serverTime: answer.serverTime, config: answer.tableConfig);
        final dc = answer.deviceConfig;
        if (dc != null) await onDeviceConfig(dc);

        // Removals first: rows deleted on the server go before the tables are applied.
        var reset = false;
        // An answer's removals part is used only when removals were asked for:
        // one that was not asked for (the server hands out its newest position)
        // must never move the saved position.
        final rem = askRemovals ? answer.removals : null;
        if (rem != null) {
          if (rem.skipped != null) {
            // Switched off or fresh: keep the saved position; take the starting
            // one only when none was ever saved.
            if (removalsPosition == null && rem.startingPosition != null) {
              await Removals.saveStartingPosition(db, rem.startingPosition!);
              removalsPosition = rem.startingPosition;
            }
            removalsPending = false;
            skippedHere.add(_removals);
          } else if (rem.page != null) {
            final page = rem.page!;
            removalsChecked = true;
            removed += await Removals.applyPage(db, page);
            if (page.nextAfterId != removalsPosition) moved = true;
            removalsPosition = page.nextAfterId;
            if (page.resetRequired) {
              reset = true;
            } else if (page.last) {
              removalsPending = false;
              freshness.markChecked(_removals, answer.serverTime);
            } else {
              removalsPending = true;
            }
          }
        } else if (askRemovals) {
          removalsPending = false;
        }

        if (reset) {
          // The tables in this answer were worked out from cursors that are no
          // longer valid: drop them, start every table again.
          if (resetDone) {
            throw StateError('the server asked for a reset twice in one pull');
          }
          resetDone = true;
          freshness.clearChecked();
          for (final f in kSyncFeeds) {
            cursor[f] = null;
          }
          pending
            ..clear()
            ..addAll(kSyncFeeds);
          removalsPending = true;
          onCall?.call(calls, asked, skippedHere, 0);
          continue;
        }

        // The tables, in the order of the contract.
        for (final f in kSyncFeeds) {
          final t = answer.tables[f];
          if (t == null) continue;
          if (t.skipped != null) {
            pending.remove(f);
            skippedHere.add(f);
            continue;
          }
          if (t.deferred || t.page == null) continue;
          final page = t.page!;
          final n = await SyncEngine.savePage(db, f, page);
          rows += n;
          rowsThisCall += n;
          final before = cursor[f];
          cursor[f] = (since: page.nextSince, afterId: page.nextAfterId);
          if (before == null ||
              before.since != page.nextSince ||
              before.afterId != page.nextAfterId) {
            moved = true;
          }
          if (page.last) {
            pending.remove(f);
            freshness.markChecked(f, answer.serverTime);
          }
        }

        onCall?.call(calls, asked, skippedHere, rowsThisCall);
        onProgress?.call(
            (kSyncFeeds.length - pending.length) + (removalsPending ? 0 : 1),
            total,
            removalsPending
                ? _removals
                : (pending.isEmpty ? 'done' : pending.first));

        if (pending.isEmpty && !removalsPending) {
          return CombinedResult(
              rows: rows,
              calls: calls,
              removed: removed,
              removalsChecked: removalsChecked);
        }
        if (!moved) {
          throw StateError('the server made no progress (${[
            ...pending,
            if (removalsPending) _removals
          ].join(', ')})');
        }
      }
    } finally {
      unfinished = [...pending, if (removalsPending) _removals];
    }
  }
}
