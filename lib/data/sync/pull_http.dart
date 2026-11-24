import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef ClientFactory = http.Client Function();

/// A client whose connect step gives up after [connectTimeout] instead of
/// waiting for the whole request limit.
http.Client connectLimitedClient(Duration connectTimeout) =>
    IOClient(HttpClient()..connectionTimeout = connectTimeout);

/// The web requests of one sync pull: one shared connection, and a retry on a
/// brand-new connection when a request got no answer at all.
///
/// Why: the path to the server sometimes swallows a new connection and says
/// nothing; a fresh connection usually works. Waiting the whole request limit
/// (30 s) on a swallowed connection failed the pull; a short connect limit and
/// another try on a new connection does not.
///
/// Retried: connect time-out, refused or reset connection, a connection that
/// closed before any answer. Never retried: any answer from the server (200,
/// 401, 429, 503 …) and the whole-request time-out for a reply that began
/// but never finished — those are handled by the caller exactly as before.
/// Only for reads: repeating them is harmless.
class PullHttp {
  PullHttp({
    required this.requestTimeout,
    this.attempts = 3,
    this.pauses = const [Duration(seconds: 1), Duration(seconds: 2)],
    this.connectTimeout = const Duration(seconds: 5),
    ClientFactory? makeClient,
    this.onRetry,
  }) : _make = makeClient ?? (() => connectLimitedClient(connectTimeout));

  final Duration requestTimeout;
  final int attempts;
  final List<Duration> pauses;
  final Duration connectTimeout;
  final ClientFactory _make;

  /// Called before each repeat: label, the attempt about to start, attempts, the error.
  final void Function(String label, int attempt, int attempts, Object error)? onRetry;

  /// How many repeats this object made (for the pull summary).
  int retries = 0;

  http.Client? _client;

  Future<http.Response> get(
    Uri uri, {
    Map<String, String> headers = const {},
    required Future<void> abort,
    String? label,
  }) async {
    final name = label ?? uri.pathSegments.last;
    for (var n = 1;; n++) {
      final client = _client ??= _make();
      Object error;
      try {
        final req = http.AbortableRequest('GET', uri, abortTrigger: abort)
          ..headers.addAll(headers);
        final streamed = await client.send(req).timeout(requestTimeout);
        return await http.Response.fromStream(streamed).timeout(requestTimeout);
      } on http.RequestAbortedException {
        rethrow;
      } on http.ClientException catch (e) {
        error = e;
      } on SocketException catch (e) {
        error = e;
      }
      if (n >= attempts) throw error;
      // The connection that failed is not used again.
      _client = null;
      client.close();
      retries++;
      onRetry?.call(name, n + 1, attempts, error);
      await _pause(pauses.isEmpty ? Duration.zero : pauses[(n - 1).clamp(0, pauses.length - 1)], abort, uri);
    }
  }

  /// A pause that ends at once when the pull is stopped (a customer came back).
  Future<void> _pause(Duration d, Future<void> abort, Uri uri) async {
    var stopped = false;
    await Future.any<void>([
      Future<void>.delayed(d),
      abort.then((_) => stopped = true),
    ]);
    if (stopped) throw http.RequestAbortedException(uri);
  }

  void close() {
    _client?.close();
    _client = null;
  }
}
