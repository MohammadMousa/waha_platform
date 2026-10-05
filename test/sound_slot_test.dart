import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/services/scan_sound_service.dart';

// Every started sound must be ended, and bursts must not create unbounded
// players (the old code never ended any, so audio players piled up).
class _FakePort implements SoundPoolPort {
  _FakePort({this.length = const Duration(milliseconds: 40), this.failStart = false});
  final Duration? length;
  final bool failStart;
  int started = 0;
  int stopped = 0;
  int peak = 0;

  int get outstanding => started - stopped;

  @override
  Future<Future<void> Function()> start() async {
    if (failStart) throw StateError('start failed');
    started++;
    if (outstanding > peak) peak = outstanding;
    return () async {
      stopped++;
    };
  }

  @override
  Future<Duration?> duration() async => length;
}

void main() {
  SoundSlot slot(_FakePort port, {int max = 3, Duration margin = const Duration(milliseconds: 10)}) =>
      SoundSlot(() async => port, maxConcurrent: max, margin: margin, fallbackLength: const Duration(milliseconds: 40));

  test('a sound is ended after its length plus the margin, and the player is handed back', () async {
    final port = _FakePort();
    final s = slot(port);
    await s.play();
    expect(port.started, 1);
    expect(port.stopped, 0);
    expect(s.playing, 1);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(port.stopped, 1);
    expect(s.playing, 0);
  });

  test('100 sounds one after another leave nothing outstanding', () async {
    final port = _FakePort(length: const Duration(milliseconds: 5));
    final s = slot(port, margin: const Duration(milliseconds: 2));
    for (var i = 0; i < 100; i++) {
      await s.play();
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(port.started, 100);
    expect(port.outstanding, 0);
    expect(s.playing, 0);
    expect(port.peak, 1);
  });

  test('a burst of 50 at once starts at most 3, never an unbounded number', () async {
    final port = _FakePort();
    final s = slot(port);
    await Future.wait([for (var i = 0; i < 50; i++) s.play()]);
    expect(port.started, 3);
    expect(port.peak, 3);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(port.outstanding, 0);
    expect(s.playing, 0);
  });

  test('an unknown length uses the fallback, so it is still ended', () async {
    final port = _FakePort(length: null);
    final s = slot(port);
    await s.play();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(port.stopped, 1);
  });

  test('a failing start leaves nothing counted as playing, and later plays still work', () async {
    var fail = true;
    final good = _FakePort();
    final s = SoundSlot(() async => fail ? _FakePort(failStart: true) : good,
        margin: const Duration(milliseconds: 10), fallbackLength: const Duration(milliseconds: 40));
    await expectLater(s.play(), throwsA(isA<StateError>()));
    expect(s.playing, 0);
    fail = false;
    await s.play();
    expect(good.started, 1);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(good.outstanding, 0);
  });

  test('the port is opened once and reused', () async {
    var opens = 0;
    final port = _FakePort();
    final s = SoundSlot(() async {
      opens++;
      return port;
    }, margin: const Duration(milliseconds: 5));
    await s.play();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await s.play();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(opens, 1);
    expect(port.started, 2);
  });
}
