import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/config/app_config.dart';
import 'package:waha_kiosk/config/connection_settings.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/connection_switcher.dart';
import 'package:waha_kiosk/services/local_prefs.dart';
import 'package:waha_kiosk/state/auth_service.dart';
import 'package:waha_kiosk/state/browsing_mode_service.dart';
import 'package:waha_kiosk/state/order_flow_controller.dart';

/// Minimal stand-in for a Waha backend: /api/config, kiosk login, stores.
Future<HttpServer> fakeServer({required String pin}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    req.response.headers.contentType = ContentType.json;
    switch ('${req.method} ${req.uri.path}') {
      case 'GET /api/config':
        req.response.write('{"appName":"{\\"en\\":\\"Fake\\"}"}');
      case 'POST /api/kiosk/auth/login':
        if ((jsonDecode(body) as Map)['pinCode'] == pin) {
          req.response.write(
              '{"token":"NEW-TOKEN","deviceId":7,"storeId":3,"mode":"KIOSK","permissions":[]}');
        } else {
          req.response.statusCode = 401;
          req.response.write('{"message":"Invalid credentials"}');
        }
      case 'GET /api/stores':
        req.response.write('[]');
      default:
        req.response.statusCode = 404;
        req.response.write('{"message":"nope"}');
    }
    await req.response.close();
  });
  return server;
}

void main() {
  late OrderFlowController order;
  late ApiClient api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'waha.kiosk_username': 'old-dev',
      'waha.kiosk_pin': '000000',
    });
    await LocalPrefs.init();
    await AppConfig.connection
        .save(enabled: false, custom: CustomConnection.empty);
    browsingModeService.setMode(BrowsingMode.kiosk, persist: false);
    authService.token = 'OLD-TOKEN';
    authService.deviceId = 1;
    api = ApiClient();
    order = OrderFlowController(api);
  });

  test('unreachable server: nothing changes', () async {
    final before = AppConfig.apiBaseUrl;
    final r = await ConnectionSwitcher.apply(
      customEnabled: true,
      custom: const CustomConnection(host: '127.0.0.1', port: 1),
      activeApi: api,
      order: order,
      credentials: const SwitchCredentials('dev', '123456'),
    );
    expect(r.ok, isFalse);
    expect(r.failedStep, 'server');
    expect(AppConfig.apiBaseUrl, before);
    expect(authService.token, 'OLD-TOKEN');
    expect(AppConfig.connection.customEnabled, isFalse);
  });

  test('wrong PIN: server reached but nothing changes', () async {
    final server = await fakeServer(pin: '123456');
    addTearDown(() => server.close(force: true));
    final before = AppConfig.apiBaseUrl;
    final r = await ConnectionSwitcher.apply(
      customEnabled: true,
      custom: CustomConnection(host: '127.0.0.1', port: server.port),
      activeApi: api,
      order: order,
      credentials: const SwitchCredentials('dev', '999999'),
    );
    expect(r.ok, isFalse);
    expect(r.failedStep, 'login');
    expect(AppConfig.apiBaseUrl, before);
    expect(authService.token, 'OLD-TOKEN');
    expect(LocalPrefs.kioskPin, '000000'); // old cache untouched on failure
  });

  test('success: switches, new token, no credentials stored, fields kept',
      () async {
    final server = await fakeServer(pin: '123456');
    addTearDown(() => server.close(force: true));
    final custom = CustomConnection(host: '127.0.0.1', port: server.port);
    final r = await ConnectionSwitcher.apply(
      customEnabled: true,
      custom: custom,
      activeApi: api,
      order: order,
      credentials: const SwitchCredentials('dev', '123456'),
    );
    expect(r.ok, isTrue, reason: r.message);
    expect(AppConfig.apiBaseUrl, custom.url);
    expect(AppConfig.apiBaseUrlLabel, endsWith('(custom)'));
    expect(authService.token, 'NEW-TOKEN');
    expect(LocalPrefs.authToken, 'NEW-TOKEN');
    expect(LocalPrefs.kioskPin, isNull);
    expect(LocalPrefs.kioskUsername, isNull);

    // Turning OFF returns to the default and keeps the saved custom fields.
    final saved = AppConfig.connection.custom;
    expect(saved, custom);
    await AppConfig.connection.setEnabled(false);
    expect(AppConfig.connection.custom, custom);
  });
}
