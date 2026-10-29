import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/state/auth_service.dart';
import 'package:waha_kiosk/state/store_config_service.dart';

/// Two device accounts on two stores; the second login must land on its own
/// store, and a sign-out must leave no store behind.
Future<HttpServer> _server() async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((req) async {
    final path = req.uri.path;
    Object body = {};
    if (path == '/api/kiosk/auth/login') {
      final b = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
      final alj = b['username'] == 'alj.kiosk';
      body = {
        'token': alj ? 'tok-alj' : 'tok-oasis',
        'deviceId': alj ? 1 : 2,
        'storeId': alj ? 10 : 20,
      };
    } else if (path == '/api/stores') {
      body = [
        {
          'id': 10,
          'name': 'alj',
          'displayName': {'en': 'Aljazeera', 'ar': 'الجزيرة'},
          'currency': 'SAR'
        },
        {
          'id': 20,
          'name': 'oasis',
          'displayName': {'en': 'Oasis', 'ar': 'الواحة'},
          'currency': 'USD'
        },
      ];
    }
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  });
  return s;
}

void main() {
  test('a new login replaces the previous account\'s store; sign-out clears it',
      () async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    final s = await _server();
    addTearDown(() => s.close(force: true));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${s.port}');
    final auth = AuthService();
    final store = storeConfigService;
    await store.clearStore();

    await auth.loginKiosk(api, 'alj.kiosk', '111111');
    expect(store.storeSlug, 'alj');
    expect(store.storeCurrency, 'SAR');

    expect(await auth.logout(api), isTrue);
    expect(store.storeId, isNull);
    expect(store.storeSlug, isNull);
    expect(store.storeCurrency, isNull);

    await auth.loginKiosk(api, 'oasis.kiosk1', '222222');
    expect(store.storeId, 20);
    expect(store.storeSlug, 'oasis');
    expect(store.storeCurrency, 'USD');
  });

  test('a login that arrives while another store is set still replaces it',
      () async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    final s = await _server();
    addTearDown(() => s.close(force: true));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${s.port}');
    final auth = AuthService();
    storeConfigService.setStore(10,
        slug: 'alj', currency: 'SAR', persist: false);

    await auth.loginKiosk(api, 'oasis.kiosk1', '222222');
    expect(storeConfigService.storeId, 20);
    expect(storeConfigService.storeSlug, 'oasis');
  });

  test('sign-out stays signed in when the server cannot be reached', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    final s = await _server();
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${s.port}');
    final auth = AuthService();
    await auth.loginKiosk(api, 'alj.kiosk', '111111');
    await s.close(force: true);

    expect(await auth.logout(api), isFalse);
    expect(auth.isLoggedIn, isTrue);
    expect(storeConfigService.storeSlug, 'alj');
  });
}
