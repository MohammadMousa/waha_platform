import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/models/auth_session.dart';
import 'package:waha_kiosk/services/api_client.dart';

void main() {
  test('AuthSession.fromJson parses organizationId', () {
    final session = AuthSession.fromJson({
      'token': 't',
      'deviceId': 2,
      'organizationId': 7,
      'storeId': 9,
      'mode': 'KIOSK',
    });
    expect(session.organizationId, 7);
  });

  test('getConfig sends orgId as a query param when given, omits it otherwise',
      () async {
    String? lastQuery;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(server.forEach((req) {
      lastQuery = req.uri.query;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"default_language":"ar",'
            '"check_landing_page_interval_minutes":"15"}');
      req.response.close();
    }));
    addTearDown(() => server.close(force: true));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

    final withOrg = await api.getConfig(orgId: 7);
    expect(lastQuery, 'orgId=7');
    expect(withOrg['default_language'], 'ar');
    expect(withOrg['check_landing_page_interval_minutes'], '15');

    await api.getConfig();
    expect(lastQuery, '');
  });
}
