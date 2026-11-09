import 'dart:async';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'feeds.dart';

/// One page from GET /api/sync/{feed}.
class PullPage {
  final List<Map<String, dynamic>> items;
  final bool last;
  final String? nextSince;
  final int nextAfterId;
  const PullPage({
    required this.items,
    required this.last,
    required this.nextSince,
    required this.nextAfterId,
  });
}

class PullUnauthorized implements Exception {
  const PullUnauthorized();
}

/// The server answered 429/503 with a Retry-After: wait that long.
class PullRetryAfter implements Exception {
  final Duration delay;
  const PullRetryAfter(this.delay);
}

/// The server answered, but with an error status (so it IS reachable).
class PullHttpError implements Exception {
  final int status;
  const PullHttpError(this.status);
  @override
  String toString() => 'HTTP $status';
}

class PullCancelled implements Exception {
  const PullCancelled();
}

/// Asks the server for one page. Must throw [PullCancelled] when [abort]
/// completes and [PullUnauthorized] on a 401. Any other failure is an
/// ordinary exception (timeout, network, 5xx).
typedef PageFetcher = Future<PullPage> Function(
  String feed, {
  String? since,
  required int afterId,
  required int size,
  required Future<void> abort,
});

/// Pulls feeds into the local database. The rules (offline.md section 2):
/// - the first request of a run starts 10 seconds before the saved cursor;
///   later pages of the same run use the cursor the server just returned;
/// - a page and its cursor are saved in ONE transaction, so a dropped
///   request or a crash saves nothing and the next run resumes cleanly;
/// - rows are written with upsert, so the overlap never duplicates anything.
class SyncEngine {
  final AppDatabase db;
  final PageFetcher fetch;
  final int pageSize;
  final Duration overlap;

  SyncEngine({
    required this.db,
    required this.fetch,
    this.pageSize = 200,
    this.overlap = const Duration(seconds: 10),
  });

  /// Pulls one feed until the server says `last`. Returns the number of rows
  /// that were new or changed (not the rows received: the overlap sends some
  /// again every time). Throws [PullCancelled] / [PullUnauthorized] / other errors
  /// without changing the saved cursor of the failed page.
  Future<int> pullFeed(
    String feed, {
    required Future<void> abort,
    Future<void> Function()? beforeEachPage,
  }) async {
    final state = await (db.select(db.syncState)
          ..where((t) => t.feed.equals(feed)))
        .getSingleOrNull();

    String? since = state?.since;
    int afterId = state?.afterId ?? 0;
    if (since != null) {
      // Back up 10 s and ask from id 0: anything written in that window is
      // sent again and simply overwritten.
      final t = DateTime.parse(since).toUtc().subtract(overlap);
      since = t.toIso8601String();
      afterId = 0;
    }

    var written = 0;
    while (true) {
      if (beforeEachPage != null) await beforeEachPage();
      final page = await fetch(feed,
          since: since, afterId: afterId, size: pageSize, abort: abort);
      await db.transaction(() async {
        written += await upsertPage(db, feed, page.items);
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final prev = await (db.select(db.syncState)
              ..where((t) => t.feed.equals(feed)))
            .getSingleOrNull();
        await db.into(db.syncState).insertOnConflictUpdate(
              SyncStateCompanion(
                feed: Value(feed),
                since: Value(page.nextSince ?? prev?.since),
                afterId: Value(page.nextSince == null
                    ? (prev?.afterId ?? 0)
                    : page.nextAfterId),
                fullPullDone:
                    Value(page.last ? true : (prev?.fullPullDone ?? false)),
                lastPullAt: Value(page.last ? nowIso : prev?.lastPullAt),
                lastError: const Value(null),
              ),
            );
      });
      if (page.last) return written;
      since = page.nextSince;
      afterId = page.nextAfterId;
    }
  }

  Future<void> recordError(String feed, String message) async {
    await db.into(db.syncState).insert(
          SyncStateCompanion(feed: Value(feed), lastError: Value(message)),
          onConflict: DoUpdate((_) => SyncStateCompanion(
              feed: Value(feed), lastError: Value(message))),
        );
  }

  /// True once every feed in [kRequiredFeeds] has finished one full pull.
  Future<bool> readyForOrders() async {
    final rows = await db.select(db.syncState).get();
    final done = {for (final r in rows) r.feed: r.fullPullDone};
    return kRequiredFeeds.every((f) => done[f] == true);
  }
}
