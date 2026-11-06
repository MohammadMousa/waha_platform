import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/sync/sync_schedule.dart';
import 'package:waha_kiosk/data/sync/sync_settings.dart';

class FixedRandom implements Random {
  final double d; // for nextDouble
  final int i; // for nextInt (returned modulo max)
  FixedRandom({this.d = 0.5, this.i = 0});
  @override
  double nextDouble() => d;
  @override
  int nextInt(int max) => i % max;
  @override
  bool nextBool() => false;
}

void main() {
  group('stagger', () {
    test('sync_stagger_seconds is clamped to 30..3600, never off', () {
      expect(SyncSchedule.clampStagger(0), 30);
      expect(SyncSchedule.clampStagger(10), 30);
      expect(SyncSchedule.clampStagger(180), 180);
      expect(SyncSchedule.clampStagger(99999), 3600);
      expect(SyncSettings.fromConfig({'sync_stagger_seconds': '5'}).staggerSeconds, 30);
      expect(const SyncSettings().staggerSeconds, 180);
    });

    test('a device always gets the same slot, inside the window', () {
      const base = Duration(seconds: 60);
      final r = FixedRandom(i: 0);
      final d1 = SyncSchedule.startDelay(base: base, deviceId: 3, staggerSeconds: 180, random: r);
      final d2 = SyncSchedule.startDelay(base: base, deviceId: 3, staggerSeconds: 180, random: r);
      expect(d1, d2);
      expect(d1 >= base, true);
      expect(d1 < base + const Duration(seconds: 180), true);
    });

    test('consecutive device ids spread over the window instead of clustering', () {
      final slots = <int>{};
      for (var id = 1; id <= 100; id++) {
        final d = SyncSchedule.startDelay(
            base: Duration.zero, deviceId: id, staggerSeconds: 180, random: FixedRandom(i: 0));
        slots.add(d.inSeconds);
        expect(d.inSeconds < 180, true);
      }
      expect(slots.length, greaterThan(60)); // 100 devices land on many different seconds
    });

    test('a wider window is respected', () {
      final d = SyncSchedule.startDelay(
          base: Duration.zero, deviceId: 7, staggerSeconds: 3600, random: FixedRandom(i: 0));
      expect(d.inSeconds < 3600, true);
    });
  });

  test('jitter adds up to the given fraction and never subtracts', () {
    const interval = Duration(minutes: 60);
    expect(SyncSchedule.withJitter(interval, 0.10, FixedRandom(d: 0)), interval);
    expect(SyncSchedule.withJitter(interval, 0.10, FixedRandom(d: 1)), const Duration(minutes: 66));
    expect(SyncSchedule.withJitter(const Duration(minutes: 10), 0.20, FixedRandom(d: 1)),
        const Duration(minutes: 12));
  });

  test('after connectivity returns the pull waits 0 to 60 seconds', () {
    expect(SyncSchedule.reconnectDelay(FixedRandom(i: 0)), Duration.zero);
    expect(SyncSchedule.reconnectDelay(FixedRandom(i: 59999)).inSeconds, 59);
  });

  group('Retry-After', () {
    test('seconds and HTTP dates', () {
      expect(SyncSchedule.parseRetryAfter('120'), const Duration(seconds: 120));
      final now = DateTime.utc(2026, 11, 6, 10, 0, 0);
      expect(SyncSchedule.parseRetryAfter('Fri, 06 Nov 2026 10:05:00 GMT', now: now),
          const Duration(minutes: 5));
    });
    test('missing, unreadable, past and huge values are handled', () {
      expect(SyncSchedule.parseRetryAfter(null), isNull);
      expect(SyncSchedule.parseRetryAfter(''), isNull);
      expect(SyncSchedule.parseRetryAfter('soon'), isNull);
      expect(SyncSchedule.parseRetryAfter('-5'), Duration.zero);
      expect(SyncSchedule.parseRetryAfter('999999'), const Duration(hours: 1));
    });
  });

  test('status is sent on change (at most once a minute) or about every ten minutes', () {
    bool send(bool changed, int seconds) => SyncSchedule.shouldSendStatus(
        changed: changed, sinceLastSend: Duration(seconds: seconds));
    expect(send(true, 20), false); // changed but too soon
    expect(send(true, 61), true);
    expect(send(false, 300), false); // nothing new, not yet ten minutes
    expect(send(false, 601), true);
  });
}
