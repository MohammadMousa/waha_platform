import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/config/app_config.dart';
import 'package:waha_kiosk/config/connection_settings.dart';

void main() {
  group('apiBaseUrl precedence', () {
    String resolve({
      bool active = false,
      String custom = '',
      String define = '',
    }) =>
        AppConfig.resolveApiBaseUrl(
          customActive: active,
          customUrl: custom,
          buildDefine: define,
          platformDefault: 'http://10.0.2.2:8081',
        );

    test('custom ON beats the build define', () {
      expect(
        resolve(
            active: true,
            custom: 'http://192.168.1.9:8080',
            define: 'https://api.x.com'),
        'http://192.168.1.9:8080',
      );
    });
    test('custom OFF returns to the build define', () {
      expect(
          resolve(
              custom: 'http://192.168.1.9:8080', define: 'https://api.x.com'),
          'https://api.x.com');
    });
    test('no define, custom OFF -> platform default', () {
      expect(
          resolve(custom: 'http://192.168.1.9:8080'), 'http://10.0.2.2:8081');
    });
  });

  group('CustomConnection', () {
    test('builds url without port or path', () {
      expect(const CustomConnection(scheme: 'https', host: 'api.x.com').url,
          'https://api.x.com');
    });
    test('builds url with port and base path', () {
      expect(
        const CustomConnection(host: '10.0.0.25', port: 8080, basePath: '/waha')
            .url,
        'http://10.0.0.25:8080/waha',
      );
    });
    test('brackets a bare IPv6 host', () {
      expect(const CustomConnection(host: '::1', port: 8081).url,
          'http://[::1]:8081');
    });
    test('validation', () {
      expect(const CustomConnection().validate(), isNotNull);
      expect(const CustomConnection(host: 'http://x').validate(), isNotNull);
      expect(
          const CustomConnection(host: 'x', port: 70000).validate(), isNotNull);
      expect(const CustomConnection(host: 'x', port: 8081).validate(), isNull);
    });
    test('fromUrl splits parts and normalises the path', () {
      final c = CustomConnection.fromUrl('https://api.x.com:8443/waha/')!;
      expect((c.scheme, c.host, c.port, c.basePath),
          ('https', 'api.x.com', 8443, '/waha'));
      expect(CustomConnection.fromUrl('http://h')!.port, isNull);
      expect(CustomConnection.fromUrl('ftp://h'), isNull);
      expect(CustomConnection.normalizeBasePath('waha//'), '/waha');
    });
  });

  group('legacy migration', () {
    test('no build define -> custom ON (same server as before)', () {
      final m = planLegacyMigration(
          legacyUrl: 'http://192.168.1.9:8081',
          hasBuildDefine: false,
          isAndroid: true)!;
      expect(m.enable, isTrue);
      expect(m.custom.host, '192.168.1.9');
    });
    test('build define -> kept but custom stays OFF', () {
      final m = planLegacyMigration(
          legacyUrl: 'http://192.168.1.9:8081',
          hasBuildDefine: true,
          isAndroid: true)!;
      expect(m.enable, isFalse);
    });
    test('android localhost was ignored before -> stays OFF', () {
      final m = planLegacyMigration(
          legacyUrl: 'http://localhost:8081',
          hasBuildDefine: false,
          isAndroid: true)!;
      expect(m.enable, isFalse);
    });
    test('nothing saved -> nothing to do', () {
      expect(
          planLegacyMigration(
              legacyUrl: null, hasBuildDefine: false, isAndroid: false),
          isNull);
    });
  });
}
