import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waha_kiosk/services/auto_restart_service.dart';
import 'package:waha_kiosk/services/local_prefs.dart';

// Scheduled restart: pure timing rules, and the two server properties.
void main() {
  group('planner', () {
    AutoRestartPlanner planner([Duration p = const Duration(hours: 2)]) => AutoRestartPlanner(period: p);

    test('nothing happens before the period has passed', () {
      final p = planner();
      expect(p.check(uptime: const Duration(minutes: 119), enabled: true, canRestartNow: true), RestartDecision.idle);
    });

    test('due and idle: start the countdown', () {
      final p = planner();
      expect(p.check(uptime: const Duration(hours: 2), enabled: true, canRestartNow: true), RestartDecision.countdown);
    });

    test('due but busy: wait 3 minutes (default), then ask again, as often as needed', () {
      final p = planner();
      const t0 = Duration(hours: 2);
      expect(p.check(uptime: t0, enabled: true, canRestartNow: false), RestartDecision.waiting);
      expect(p.check(uptime: t0 + const Duration(minutes: 2, seconds: 59), enabled: true, canRestartNow: true), RestartDecision.idle);
      expect(p.check(uptime: t0 + const Duration(minutes: 3), enabled: true, canRestartNow: false), RestartDecision.waiting);
      expect(p.check(uptime: t0 + const Duration(minutes: 6), enabled: true, canRestartNow: false), RestartDecision.waiting);
      expect(p.check(uptime: t0 + const Duration(minutes: 9), enabled: true, canRestartNow: true), RestartDecision.countdown);
    });

    test('the wait is configurable', () {
      final p = AutoRestartPlanner(period: const Duration(hours: 2), wait: const Duration(minutes: 1));
      const t0 = Duration(hours: 2);
      expect(p.check(uptime: t0, enabled: true, canRestartNow: false), RestartDecision.waiting);
      expect(p.check(uptime: t0 + const Duration(seconds: 59), enabled: true, canRestartNow: true), RestartDecision.idle);
      expect(p.check(uptime: t0 + const Duration(minutes: 1), enabled: true, canRestartNow: true), RestartDecision.countdown);
      p.setWait(const Duration(minutes: 10));
      expect(p.wait, const Duration(minutes: 10));
    });

    test('disabled: never', () {
      final p = planner();
      expect(p.check(uptime: const Duration(hours: 50), enabled: false, canRestartNow: true), RestartDecision.idle);
    });

    test('never in the first 10 minutes, whatever the period', () {
      final p = planner(const Duration(minutes: 1));
      expect(p.check(uptime: const Duration(minutes: 9), enabled: true, canRestartNow: true), RestartDecision.idle);
      expect(p.check(uptime: const Duration(minutes: 10), enabled: true, canRestartNow: true), RestartDecision.countdown);
    });

    test('"Not now" waits the same time, then it asks again', () {
      final p = planner();
      const t0 = Duration(hours: 2);
      expect(p.check(uptime: t0, enabled: true, canRestartNow: true), RestartDecision.countdown);
      p.snoozed(t0);
      expect(p.check(uptime: t0 + const Duration(minutes: 2), enabled: true, canRestartNow: true), RestartDecision.idle);
      expect(p.check(uptime: t0 + const Duration(minutes: 3), enabled: true, canRestartNow: true), RestartDecision.countdown);
    });

    test('a changed period takes effect', () {
      final p = planner();
      p.setPeriod(const Duration(hours: 4));
      expect(p.check(uptime: const Duration(hours: 3), enabled: true, canRestartNow: true), RestartDecision.idle);
      expect(p.check(uptime: const Duration(hours: 4), enabled: true, canRestartNow: true), RestartDecision.countdown);
    });
  });

  group('idle rule', () {
    bool idle({bool kiosk = true, bool landing = true, bool cartEmpty = true, bool noOrder = true, bool noPayment = true, bool noPending = true}) =>
        AutoRestartService.isIdle(
          kioskMode: kiosk, onLanding: landing, cartEmpty: cartEmpty,
          noOrder: noOrder, noPayment: noPayment, noPendingAttempt: noPending,
        );

    test('idle only when everything is quiet', () {
      expect(idle(), isTrue);
    });

    test('any one busy sign blocks it', () {
      expect(idle(kiosk: false), isFalse);
      expect(idle(landing: false), isFalse);
      expect(idle(cartEmpty: false), isFalse);
      expect(idle(noOrder: false), isFalse);
      expect(idle(noPayment: false), isFalse);
      expect(idle(noPending: false), isFalse);
    });
  });

  group('properties', () {
    Future<void> prefs(Map<String, Object> v) async {
      SharedPreferences.setMockInitialValues(v);
      await LocalPrefs.init();
    }

    test('period: default 2 hours, decimals allowed, junk falls back, limits applied', () {
      expect(AutoRestartService.parsePeriodHours(null), 2.0);
      expect(AutoRestartService.parsePeriodHours(''), 2.0);
      expect(AutoRestartService.parsePeriodHours('abc'), 2.0);
      expect(AutoRestartService.parsePeriodHours('0'), 2.0);
      expect(AutoRestartService.parsePeriodHours('-3'), 2.0);
      expect(AutoRestartService.parsePeriodHours('3'), 3.0);
      expect(AutoRestartService.parsePeriodHours(' 1.5 '), 1.5);
      expect(AutoRestartService.parsePeriodHours('0.01'), 0.25);
      expect(AutoRestartService.parsePeriodHours('99999'), 168.0);
    });

    test('wait: default 3 minutes, whole minutes, junk falls back, limits applied', () {
      expect(AutoRestartService.parseWaitMinutes(null), 3);
      expect(AutoRestartService.parseWaitMinutes('abc'), 3);
      expect(AutoRestartService.parseWaitMinutes('0'), 3);
      expect(AutoRestartService.parseWaitMinutes('-2'), 3);
      expect(AutoRestartService.parseWaitMinutes('5'), 5);
      expect(AutoRestartService.parseWaitMinutes(' 10 '), 10);
      expect(AutoRestartService.parseWaitMinutes('500'), 60);
    });

    test('off by default, 2 hours, wait 3 minutes', () async {
      await prefs({});
      expect(LocalPrefs.autoRestartEnabled, isFalse);
      expect(LocalPrefs.autoRestartPeriodHours, 2.0);
      expect(LocalPrefs.autoRestartWaitMinutes, 3);
    });

    test('the server values are stored', () async {
      await prefs({});
      await AutoRestartService.applyConfig({
        'device_auto_restart_enabled': 'true',
        'device_auto_restart_hours': '3',
        'device_auto_restart_wait_minutes': '7',
      });
      expect(LocalPrefs.autoRestartEnabled, isTrue);
      expect(LocalPrefs.autoRestartPeriodHours, 3.0);
      expect(LocalPrefs.autoRestartWaitMinutes, 7);
    });

    test('a missing property counts as off and the defaults', () async {
      await prefs({
        'waha.auto_restart_enabled': true,
        'waha.auto_restart_period_hours': 5.0,
        'waha.auto_restart_wait_minutes': 9,
      });
      await AutoRestartService.applyConfig({'default_language': 'en'});
      expect(LocalPrefs.autoRestartEnabled, isFalse);
      expect(LocalPrefs.autoRestartPeriodHours, 2.0);
      expect(LocalPrefs.autoRestartWaitMinutes, 3);
    });

    test('a failed request (empty config) changes nothing', () async {
      await prefs({
        'waha.auto_restart_enabled': true,
        'waha.auto_restart_period_hours': 5.0,
        'waha.auto_restart_wait_minutes': 9,
      });
      await AutoRestartService.applyConfig({});
      expect(LocalPrefs.autoRestartEnabled, isTrue);
      expect(LocalPrefs.autoRestartPeriodHours, 5.0);
      expect(LocalPrefs.autoRestartWaitMinutes, 9);
    });
  });
}
