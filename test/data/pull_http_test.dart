import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waha_kiosk/data/sync/pull_http.dart';

/// Fails the first [failures] connections (a client is "a connection" here),
/// then answers with [status].
class _Fixture {
  _Fixture(this.failures, {this.status = 200, this.error});
  final int failures;
  final int status;
  final Object Function(Uri)? error;
  int clientsMade = 0;
  int requests = 0;

  http.Client make() {
    final n = ++clientsMade;
    return MockClient((req) async {
      requests++;
      if (n <= failures) {
        throw error?.call(req.url) ?? http.ClientException('Connection timed out', req.url);
      }
      return http.Response('{"ok":true}', status);
    });
  }
}

PullHttp _http(_Fixture f, {int attempts = 3, List<String>? log}) => PullHttp(
      requestTimeout: const Duration(seconds: 5),
      attempts: attempts,
      pauses: const [Duration.zero, Duration.zero],
      makeClient: f.make,
      onRetry: (label, n, total, e) => log?.add('$label $n/$total'),
    );

final _uri = Uri.parse('https://example.test/api/sync/products');

void main() {
  test('first connection fails, the retry on a new connection answers', () async {
    final f = _Fixture(1);
    final log = <String>[];
    final h = _http(f, log: log);
    final r = await h.get(_uri, abort: Completer<void>().future);
    expect(r.statusCode, 200);
    expect(f.clientsMade, 2);
    expect(h.retries, 1);
    expect(log, ['products 2/3']);
  });

  test('a shared connection is reused when nothing fails', () async {
    final f = _Fixture(0);
    final h = _http(f);
    await h.get(_uri, abort: Completer<void>().future);
    await h.get(_uri, abort: Completer<void>().future);
    expect(f.clientsMade, 1);
    expect(h.retries, 0);
  });

  test('a socket error is retried too', () async {
    final f = _Fixture(2, error: (u) => const SocketException('Connection reset'));
    final h = _http(f);
    final r = await h.get(_uri, abort: Completer<void>().future);
    expect(r.statusCode, 200);
    expect(h.retries, 2);
  });

  test('a server answer is never retried', () async {
    for (final s in [401, 429, 503, 500]) {
      final f = _Fixture(0, status: s);
      final h = _http(f);
      final r = await h.get(_uri, abort: Completer<void>().future);
      expect(r.statusCode, s);
      expect(f.requests, 1);
      expect(h.retries, 0);
    }
  });

  test('all attempts fail: the last error is thrown, after exactly 3 tries', () async {
    final f = _Fixture(99);
    final h = _http(f);
    await expectLater(h.get(_uri, abort: Completer<void>().future),
        throwsA(isA<http.ClientException>()));
    expect(f.requests, 3);
    expect(h.retries, 2);
  });

  test('attempts = 1 behaves like before (no retry)', () async {
    final f = _Fixture(1);
    final h = _http(f, attempts: 1);
    await expectLater(h.get(_uri, abort: Completer<void>().future),
        throwsA(isA<http.ClientException>()));
    expect(f.requests, 1);
  });

  test('a reply that never finishes hits the whole-request limit and is not retried', () async {
    var requests = 0;
    final h = PullHttp(
      requestTimeout: const Duration(milliseconds: 50),
      pauses: const [Duration.zero],
      makeClient: () => MockClient((req) async {
        requests++;
        await Completer<void>().future; // never answers
        return http.Response('', 200);
      }),
    );
    await expectLater(h.get(_uri, abort: Completer<void>().future), throwsA(isA<TimeoutException>()));
    expect(requests, 1);
  });

  test('the pull being stopped during the pause ends it at once', () async {
    final f = _Fixture(99);
    final abort = Completer<void>();
    final h = PullHttp(
      requestTimeout: const Duration(seconds: 5),
      pauses: const [Duration(seconds: 30)],
      makeClient: f.make,
    );
    final result = h.get(_uri, abort: abort.future);
    final check = expectLater(result, throwsA(isA<http.RequestAbortedException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    abort.complete();
    await check;
    expect(f.requests, 1);
  });
}
