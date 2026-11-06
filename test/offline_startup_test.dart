import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/state/auth_service.dart';
import 'package:waha_kiosk/state/permission_service.dart';
import 'package:waha_kiosk/state/store_config_service.dart';

/// [meStatus] is what /me answers: 200 confirms, 401 rejects the login.
Future<HttpServer> _server(int Function() meStatus) async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((req) async {
    Object body = {};
    var status = 200;
    switch (req.uri.path) {
      case '/api/kiosk/auth/login':
        await utf8.decoder.bind(req).join();
        body = {
          'token': 'tok-1',
          'deviceId': 7,
          'storeId': 10,
          'organizationId': 3,
          'permissions': ['SELL', 'UPLOAD_LOGS'],
        };
      case '/api/kiosk/auth/me':
        status = meStatus();
        body = {'deviceId': 7, 'storeId': 10, 'organizationId': 3};
      case '/api/stores':
        body = [
          {
            'id': 10,
            'name': 'alj',
            'displayName': {'en': 'Aljazeera', 'ar': 'الجزيرة'},
            'currency': 'SAR'
          },
        ];
    }
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  });
  return s;
}

void main() {
  var me = 200;
  late HttpServer server;
  late ApiClient api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPrefs.init();
    await storeConfigService.clearStore();
    permissionService.clear();
    me = 200;
    server = await _server(() => me);
    api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
  });
  tearDown(() => server.close(force: true));

  Future<void> forgetMemory() async {
    await storeConfigService.clearStore();
    permissionService.clear();
  }

  test('a signed-in device reopens from its saved session without the server',
      () async {
    await AuthService().loginKiosk(api, 'alj.kiosk', '111111');
    await forgetMemory();

    final fresh = AuthService();
    expect(await fresh.restoreSavedSession(), isTrue);
    expect(fresh.token, 'tok-1');
    expect(fresh.isDeviceSession, isTrue);
    expect(fresh.deviceId, 7);
    expect(fresh.organizationId, 3);
    expect(permissionService.can('SELL'), isTrue);
    expect(storeConfigService.storeId, 10);
    expect(storeConfigService.storeCurrency, 'SAR');
    expect(storeConfigService.storeSlug, 'alj');
    expect(LocalPrefs.authToken, 'tok-1'); // nobody was signed out
  });

  test('with nothing saved there is no offline start', () async {
    expect(await AuthService().restoreSavedSession(), isFalse);

    // a token from an older build, but no saved details yet
    await LocalPrefs.setAuthToken('old');
    expect(await AuthService().restoreSavedSession(), isFalse);
  });

  test('sign-out removes the saved session with the token', () async {
    final auth = AuthService();
    await auth.loginKiosk(api, 'alj.kiosk', '111111');
    expect(LocalPrefs.sessionSnapshot, isNotNull);
    await auth.logout(api);
    expect(LocalPrefs.sessionSnapshot, isNull);
    expect(await AuthService().restoreSavedSession(), isFalse);
  });

  test('a real 401 signs out; an unreachable server does not', () async {
    await AuthService().loginKiosk(api, 'alj.kiosk', '111111');

    // server gone: login and saved session stay
    final dead = ApiClient(baseUrl: 'http://127.0.0.1:1');
    await AuthService().resolveStartupAuth(dead);
    expect(LocalPrefs.authToken, 'tok-1');
    expect(LocalPrefs.sessionSnapshot, isNotNull);

    // server says the login is invalid: both go
    me = 401;
    await AuthService().resolveStartupAuth(api);
    expect(LocalPrefs.authToken, isNull);
    expect(LocalPrefs.sessionSnapshot, isNull);
  });
}
