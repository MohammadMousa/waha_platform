import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/api_exceptions.dart';

Future<HttpServer> _server(int status, Map<String, dynamic> body) async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((req) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  });
  return s;
}

void main() {
  test('401 INVALID_CREDENTIALS carries attempts remaining', () async {
    final s = await _server(401, {
      'code': 'INVALID_CREDENTIALS',
      'message': 'Invalid username or PIN.',
      'attempts_remaining': 2,
      'max_attempts': 5,
    });
    addTearDown(() => s.close(force: true));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${s.port}');
    try {
      await api.kioskLogin('u', '1');
      fail('should throw');
    } on InvalidCredentialsException catch (e) {
      expect(e.attemptsRemaining, 2);
      expect(loginFailureText(e),
          'Invalid credentials. 2 attempts remaining before temporary lock.');
    }
  });

  test('429 ACCOUNT_LOCKED carries the wait, shown as mm:ss', () async {
    final s = await _server(429, {
      'code': 'ACCOUNT_LOCKED',
      'message': 'Too many failed attempts. Account temporarily locked.',
      'retry_after_seconds': 299,
    });
    addTearDown(() => s.close(force: true));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${s.port}');
    try {
      await api.kioskLogin('u', '1');
      fail('should throw');
    } on AccountLockedException catch (e) {
      expect(e.retryAfterSeconds, 299);
      expect(loginFailureText(e),
          'Account temporarily locked. Try again in 04:59');
    }
  });

  test('old backend 401 with a plain message still shows that message',
      () async {
    final s = await _server(401, {'message': 'Invalid credentials'});
    addTearDown(() => s.close(force: true));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${s.port}');
    try {
      await api.login('u', 'p');
      fail('should throw');
    } on ApiException catch (e) {
      expect(loginFailureText(e), 'Invalid credentials');
    }
  });

  test('429 TOO_MANY_REQUESTS shows the backend message with the countdown',
      () async {
    final s = await _server(429, {
      'code': 'TOO_MANY_REQUESTS',
      'message': 'Too many requests — please try again later.',
      'retry_after_seconds': 847,
    });
    addTearDown(() => s.close(force: true));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${s.port}');
    try {
      await api.kioskLogin('u', '1');
      fail('should throw');
    } on AccountLockedException catch (e) {
      expect(e.isIpThrottle, isTrue);
      expect(loginFailureText(e),
          'Too many requests — please try again later. Try again in 14:07');
    }
  });
}
