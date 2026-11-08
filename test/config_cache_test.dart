import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/data/catalog/offline_level.dart';
import 'package:waha_kiosk/data/sync/sync_settings.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  Future<void> fresh([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    await LocalPrefs.init();
  }

  group('offline_mode value', () {
    test('off, caching, full; old true/false; anything else is off', () {
      expect(OfflineLevel.parse('off'), OfflineLevel.off);
      expect(OfflineLevel.parse('caching'), OfflineLevel.caching);
      expect(OfflineLevel.parse('full'), OfflineLevel.full);
      expect(OfflineLevel.parse('FULL'), OfflineLevel.full);
      expect(OfflineLevel.parse('true'), OfflineLevel.full);
      expect(OfflineLevel.parse('false'), OfflineLevel.off);
      expect(OfflineLevel.parse(null), OfflineLevel.off);
      expect(OfflineLevel.parse('banana'), OfflineLevel.off);
    });

    test('settings: only full counts as offline mode', () {
      expect(SyncSettings.fromConfig({'offline_mode': 'full'}).offlineMode, isTrue);
      expect(SyncSettings.fromConfig({'offline_mode': 'caching'}).offlineMode, isFalse);
      expect(SyncSettings.fromConfig({'offline_mode': 'caching'}).offlineLevel,
          OfflineLevel.caching);
      expect(const SyncSettings().offlineLevel, OfflineLevel.off);
    });
  });

  group('saved config', () {
    test('survives, drives the mode, the VAT label and scan_disabled_products',
        () async {
      await fresh();
      expect(LocalPrefs.offlineLevel, OfflineLevel.off);
      await LocalPrefs.saveConfig({
        'offline_mode': 'caching',
        'prices_exclude_vat': 'true',
        'scan_disabled_products': 'true',
        'sync_stagger_seconds': '90',
      });
      expect(LocalPrefs.offlineLevel, OfflineLevel.caching);
      expect(LocalPrefs.pricesExcludeVat, isTrue);
      expect(LocalPrefs.scanDisabledProducts, isTrue);
      expect(LocalPrefs.savedConfig['sync_stagger_seconds'], '90');
      // a missing VAT key in a saved config is the default: VAT included
      await LocalPrefs.saveConfig({'offline_mode': 'full'});
      expect(LocalPrefs.pricesExcludeVat, isFalse);
      expect(LocalPrefs.offlineMode, isTrue);
    });

    test('an empty answer never overwrites the saved copy', () async {
      await fresh();
      await LocalPrefs.saveConfig({'offline_mode': 'full'});
      await LocalPrefs.saveConfig({});
      expect(LocalPrefs.savedConfig['offline_mode'], 'full');
    });

    test('a device saved before (true/false) keeps working', () async {
      await fresh({'waha.offline_mode': true});
      expect(LocalPrefs.offlineLevel, OfflineLevel.full);
      await fresh({'waha.offline_mode': false});
      expect(LocalPrefs.offlineLevel, OfflineLevel.off);
    });
  });

  group('getConfig keeps the answer', () {
    late HttpServer server;
    late Map<String, String> answer;
    late ApiClient api;

    setUp(() async {
      await fresh();
      answer = {'offline_mode': 'caching', 'sync_stagger_seconds': '60'};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(answer))
          ..close();
      });
      api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    });
    tearDown(() => server.close(force: true));

    test('an organization answer is saved and replaces the old copy', () async {
      await api.getConfig(orgId: 1);
      expect(LocalPrefs.offlineLevel, OfflineLevel.caching);
      answer = {'offline_mode': 'full'};
      await api.getConfig(orgId: 1);
      expect(LocalPrefs.offlineLevel, OfflineLevel.full);
    });

    test('the public answer only fills an empty copy', () async {
      await api.getConfig(); // nothing saved yet: saved
      expect(LocalPrefs.offlineLevel, OfflineLevel.caching);
      answer = {'offline_mode': 'off'};
      await api.getConfig(); // public again: must not overwrite
      expect(LocalPrefs.offlineLevel, OfflineLevel.caching);
      await api.getConfig(orgId: 1); // the organization's own: replaces
      expect(LocalPrefs.offlineLevel, OfflineLevel.off);
    });

    test('server down: empty answer, saved copy untouched', () async {
      await api.getConfig(orgId: 1);
      await server.close(force: true);
      expect(await api.getConfig(orgId: 1), isEmpty);
      expect(LocalPrefs.offlineLevel, OfflineLevel.caching);
    });
  });
}
