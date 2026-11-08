import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../db/app_database.dart';
import 'resource_settings.dart';

/// A saved resource: the file to show and what the server said it is.
class SavedResource {
  final String address;
  final File file;
  final String mimeType;
  const SavedResource(this.address, this.file, this.mimeType);
}

/// The lazy resource cache: product images, the landing page, and the files
/// the landing page uses. One cache for every mode (off, caching, full).
///
/// HOW IT WORKS — read before changing it:
///  - Lazy. Nothing is downloaded in advance. A resource is fetched the first
///    time a screen asks for it, saved, and served from disk from then on.
///  - Keyed by the ADDRESS that was asked for ("/api/resources/125",
///    "/resource/waha/pages/home.png"). The server's own resource tables are
///    not mirrored.
///  - The bytes are files in one folder named by their sha256, so identical
///    bytes reached by two addresses are stored once; the table
///    (cached_resources) says address -> file.
///  - By-id addresses (/api/resources/<id>) are content-addressed on the
///    server: an id always means the same bytes, a replaced image gets a NEW
///    id. They are never revalidated.
///  - Path addresses (/resource/...) keep their address when the content
///    changes. They are revalidated with the saved ETag sent VERBATIM in
///    If-None-Match (the server compares for exact equality: no W/ prefix, no
///    list, no *). 304 keeps the file; 200 replaces it; 404 deletes it. At most
///    one check per file per [ResourceSettings.recheckMinutes].
///  - The saved copy shows until the new one has FULLY arrived: the download
///    goes to a temporary file and is swapped in only when complete. A failed
///    download changes nothing.
///  - Offline (or any failure) never loses what is saved: the saved file is
///    served and the check is skipped.
///  - Never cached: logs (/api/logs/...), and any answer that is not a 2xx.
class ResourceCache {
  final AppDatabase db;
  final Directory dir;
  final http.Client _client;
  final DateTime Function() _now;
  final String Function() _baseUrl;
  final Map<String, String> Function() _headers;
  final bool Function() _canReach;
  ResourceSettings Function() settings;

  /// Addresses the cleanup must keep: the landing page and the files it uses.
  final Future<Set<String>> Function() _pinned;

  /// True when nobody is using the screen (cleanup waits for that).
  final bool Function() _isIdle;

  /// Refuse anything bigger than this (a safety net, not a policy).
  final int maxFileBytes;

  ResourceCache({
    required this.db,
    required this.dir,
    required String Function() baseUrl,
    Map<String, String> Function()? headers,
    bool Function()? canReach,
    http.Client? client,
    DateTime Function()? now,
    ResourceSettings Function()? settings,
    Future<Set<String>> Function()? pinned,
    bool Function()? isIdle,
    this.maxFileBytes = 25 * 1024 * 1024,
  })  : _baseUrl = baseUrl,
        _pinned = pinned ?? (() async => const <String>{}),
        _isIdle = isIdle ?? (() => true),
        _headers = headers ?? (() => const {}),
        _canReach = canReach ?? (() => true),
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        settings = settings ?? (() => const ResourceSettings());

  final _changes = StreamController<String>.broadcast();

  /// Emits an address when its saved copy was replaced by a newer one (or
  /// deleted because the server no longer has it). Screens listen and redraw.
  Stream<String> get changes => _changes.stream;

  final Map<String, Future<SavedResource?>> _downloading = {};
  final Map<String, Future<void>> _checking = {};
  final Map<String, DateTime> _failedAt = {};

  /// True for an address that must never be saved.
  static bool neverCached(String address) =>
      address.startsWith('/api/logs');

  /// By-id addresses never change their bytes (see the class comment).
  static bool isById(String address) =>
      RegExp(r'^/api/resources/\d+$').hasMatch(address);

  String _iso(DateTime t) => t.toUtc().toIso8601String();

  Future<SavedResource?> peek(String address) async {
    final row = await _row(address);
    if (row == null) return null;
    final f = _fileOf(row.fileHash);
    return await f.exists() ? SavedResource(address, f, row.mimeType) : null;
  }

  /// The resource for [address]: the saved copy at once if there is one
  /// (a changed version is fetched in the background and announced on
  /// [changes]); otherwise it is downloaded now. Null when it is not saved
  /// and cannot be fetched (the caller shows its placeholder).
  Future<SavedResource?> get(String address) async {
    if (neverCached(address)) return null;
    final row = await _row(address);
    if (row != null) {
      final f = _fileOf(row.fileHash);
      if (await f.exists()) {
        await _touch(row);
        if (!isById(address) && _due(row)) _checkInBackground(address);
        return SavedResource(address, f, row.mimeType);
      }
      // The row points at a file that is gone: fetch it again.
    }
    return _downloading[address] ??= _download(address).whenComplete(() {
      _downloading.remove(address);
    });
  }

  /// Downloads [address] now, whatever is saved, and replaces the saved copy
  /// (the landing page, when its hash told us it changed). The old copy stays
  /// until the new one has fully arrived. Null on any failure.
  Future<SavedResource?> refresh(String address) async {
    if (neverCached(address) || !_canReach()) return null;
    final previous = await _row(address);
    try {
      final resp = await _client
          .get(_uri(address), headers: _headers())
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final saved = await _save(address, resp, previous: previous);
      if (saved != null && previous != null && previous.fileHash != saved.file.path.split('/').last) {
        _changes.add(address);
      }
      return saved;
    } catch (_) {
      return null;
    }
  }

  /// Completes when every check started in the background has finished
  /// (used by tests and by shutdown).
  Future<void> whenIdle() async {
    while (_checking.isNotEmpty) {
      await Future.wait(_checking.values.toList());
    }
  }

  // ---- checking a path address for a newer version -------------------------

  bool _due(CachedResource row) {
    if (!_canReach()) return false;
    final failed = _failedAt[row.address];
    final every = settings().recheck;
    if (failed != null && _now().difference(failed) < every) return false;
    final last = DateTime.tryParse(row.lastCheckedAt);
    return last == null || _now().toUtc().difference(last) >= every;
  }

  void _checkInBackground(String address) {
    _checking[address] ??= _check(address).whenComplete(() {
      _checking.remove(address);
    });
  }

  Future<void> _check(String address) async {
    try {
      final row = await _row(address);
      if (row == null) return;
      final resp = await _client
          .get(_uri(address), headers: {
            ..._headers(),
            if (row.etag != null) 'If-None-Match': row.etag!,
          })
          .timeout(const Duration(seconds: 10));
      final now = _iso(_now());
      if (resp.statusCode == 304) {
        await (db.update(db.cachedResources)..where((t) => t.address.equals(address)))
            .write(CachedResourcesCompanion(lastCheckedAt: Value(now)));
        _failedAt.remove(address);
      } else if (resp.statusCode == 200) {
        final saved = await _save(address, resp, previous: row);
        if (saved != null) {
          _failedAt.remove(address);
          _changes.add(address);
        }
      } else if (resp.statusCode == 404) {
        // The server no longer has it: do not keep showing it.
        await _remove(row);
        _changes.add(address);
      } else {
        _failedAt[address] = _now();
      }
    } catch (_) {
      _failedAt[address] = _now(); // keep the saved copy, try later
    }
  }

  // ---- downloading --------------------------------------------------------

  Future<SavedResource?> _download(String address) async {
    if (!_canReach()) return null;
    try {
      final resp = await _client
          .get(_uri(address), headers: _headers())
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null; // errors are never saved
      return await _save(address, resp);
    } catch (_) {
      return null;
    }
  }

  /// Writes a 200 answer: temporary file first, swapped in only when
  /// complete, then the row. Returns null when it is not acceptable.
  Future<SavedResource?> _save(String address, http.Response resp,
      {CachedResource? previous}) async {
    final bytes = resp.bodyBytes;
    if (bytes.isEmpty || bytes.length > maxFileBytes) return null;
    final mime = (resp.headers['content-type'] ?? 'application/octet-stream')
        .split(';')
        .first
        .trim();
    final hash = sha256.convert(bytes).toString();
    await dir.create(recursive: true);
    final target = _fileOf(hash);
    if (!await target.exists()) {
      final tmp = File('${dir.path}/tmp-${_rand()}');
      try {
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(target.path); // the swap: all or nothing
      } catch (_) {
        if (await tmp.exists()) await tmp.delete();
        return null;
      }
    }
    final now = _iso(_now());
    await db.into(db.cachedResources).insertOnConflictUpdate(
          CachedResourcesCompanion.insert(
            address: address,
            mimeType: mime,
            etag: Value(resp.headers['etag']),
            fileHash: hash,
            sizeBytes: bytes.length,
            createdAt: previous?.createdAt ?? now,
            lastCheckedAt: now,
            lastUsedAt: now,
          ),
        );
    _cleanupSoon();
    // The old bytes go only after the new row is in place, and only when no
    // other address still uses them.
    if (previous != null && previous.fileHash != hash) {
      await _deleteFileIfUnused(previous.fileHash);
    }
    return SavedResource(address, target, mime);
  }


  // ---- cleanup ---------------------------------------------------------------
  //
  // What is removed, and why (the three limits come from the server):
  //  1. Not shown for resource_cache_max_age_days (counted from the LAST TIME
  //     IT WAS SHOWN, not from the download): a file that is shown regularly
  //     never expires, however old it is.
  //  2. Over resource_cache_max_mb in total: the least recently shown go first,
  //     until the total is about 90% of the cap.
  //  3. Files nothing points to (left over from a crash) and old temporary
  //     files.
  // Never removed: the landing page and the files it uses, anything being
  // downloaded or checked, and ANYTHING while the server cannot be reached
  // (after an outage a removed file could not come back, and a normal-looking
  // page would turn into placeholders). A changed or deleted resource is not a
  // reason for this cleanup: it is replaced or deleted when it is next shown.

  Timer? _cleanupTimer;
  bool _cleaning = false;

  /// Cleanup soon after something was saved, but only when the screen is idle
  /// and the server answers; otherwise it tries again a little later.
  void _cleanupSoon() {
    _cleanupTimer ??= Timer(cleanupDelay, () async {
      _cleanupTimer = null;
      if (!_canReach()) return; // offline: nothing is removed, and no retry storm
      if (!_isIdle()) {
        _cleanupSoon();
        return;
      }
      await cleanup();
    });
  }

  /// How long after a save the cleanup runs (a test can make it short).
  Duration cleanupDelay = const Duration(minutes: 2);

  /// Starts the once-a-day cleanup (also catches age-only removals when
  /// nothing new was saved).
  Timer? _daily;
  void startDailyCleanup() {
    _daily ??= Timer.periodic(const Duration(hours: 24), (_) {
      if (_canReach() && _isIdle()) cleanup();
    });
  }

  /// Runs the cleanup now. Returns how many saved addresses were removed.
  /// Does nothing (returns 0) when the server cannot be reached.
  Future<int> cleanup() async {
    if (_cleaning || !_canReach()) return 0;
    _cleaning = true;
    var removed = 0;
    try {
      final cfg = settings();
      final pinned = await _pinned();
      bool keep(CachedResource r) =>
          pinned.contains(r.address) ||
          _downloading.containsKey(r.address) ||
          _checking.containsKey(r.address);

      // 1. not shown for too long
      final cutoff = _now().toUtc().subtract(cfg.maxAge);
      var rows = await db.select(db.cachedResources).get();
      for (final r in rows) {
        final used = DateTime.tryParse(r.lastUsedAt);
        if (used != null && used.isBefore(cutoff) && !keep(r)) {
          await _remove(r);
          removed++;
        }
      }

      // 2. over the size cap: the least recently shown first
      rows = await db.select(db.cachedResources).get();
      int total() {
        final seen = <String>{};
        var sum = 0;
        for (final r in rows) {
          if (seen.add(r.fileHash)) sum += r.sizeBytes;
        }
        return sum;
      }

      if (total() > cfg.maxBytes) {
        final target = (cfg.maxBytes * 0.9).round();
        final order = rows.where((r) => !keep(r)).toList()
          ..sort((a, b) => a.lastUsedAt.compareTo(b.lastUsedAt));
        for (final r in order) {
          if (total() <= target) break;
          await _remove(r);
          rows = rows.where((x) => x.address != r.address).toList();
          removed++;
        }
      }

      // 3. files nothing points to, and old temporary files
      await _removeOrphans();
    } finally {
      _cleaning = false;
    }
    return removed;
  }

  Future<void> _removeOrphans() async {
    if (!await dir.exists()) return;
    final known = {
      for (final r in await db.select(db.cachedResources).get()) r.fileHash
    };
    final old = _now().subtract(const Duration(minutes: 10));
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.path.split('/').last;
      try {
        if (name.startsWith('tmp-')) {
          // a download that is still being written is younger than this
          if ((await e.lastModified()).isBefore(old)) await e.delete();
        } else if (!known.contains(name)) {
          await e.delete();
        }
      } catch (_) {}
    }
  }

  // ---- small helpers --------------------------------------------------------

  Uri _uri(String address) {
    final base = _baseUrl().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$address');
  }

  File _fileOf(String hash) => File('${dir.path}/$hash');

  Future<CachedResource?> _row(String address) => (db.select(db.cachedResources)
        ..where((t) => t.address.equals(address)))
      .getSingleOrNull();

  Future<void> _touch(CachedResource row) async {
    // Not on every redraw: once a minute is plenty for "last shown".
    final last = DateTime.tryParse(row.lastUsedAt);
    if (last != null && _now().toUtc().difference(last) < const Duration(minutes: 1)) {
      return;
    }
    await (db.update(db.cachedResources)..where((t) => t.address.equals(row.address)))
        .write(CachedResourcesCompanion(lastUsedAt: Value(_iso(_now()))));
  }

  Future<void> _remove(CachedResource row) async {
    await (db.delete(db.cachedResources)..where((t) => t.address.equals(row.address))).go();
    await _deleteFileIfUnused(row.fileHash);
  }

  Future<void> _deleteFileIfUnused(String hash) async {
    final still = await (db.select(db.cachedResources)
          ..where((t) => t.fileHash.equals(hash))
          ..limit(1))
        .get();
    if (still.isNotEmpty) return;
    final f = _fileOf(hash);
    if (await f.exists()) await f.delete();
  }

  static String _rand() =>
      Random().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');

  void dispose() {
    _cleanupTimer?.cancel();
    _daily?.cancel();
    _changes.close();
  }
}
