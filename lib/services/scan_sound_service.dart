import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

/// Plays sound effects on scan events, from assets/sounds/.
///
/// Uses [AudioPool] — audioplayers' own API for "extremely quick firing,
/// repetitive ... sounds" — with `PlayerMode.lowLatency`, which on Android
/// is backed by `SoundPool` instead of `MediaPlayer`. A single shared
/// `AudioPlayer` reused with fresh `play()` calls (the original approach)
/// reloads/re-prepares the source on every call — `MediaPlayer`'s prepare
/// cycle is commonly 100-300ms on Android, long enough that a second play
/// issued in quick succession lands on a player still mid-teardown from the
/// first and gets silently dropped by the platform side (never surfaced as
/// a Dart exception). `AudioPool` preloads the asset once and hands out
/// pre-primed players from a pool, and `SoundPool`-backed playback has no
/// per-play prepare step at all.
///
/// IMPORTANT — every started sound must be ended by the caller. In
/// `PlayerMode.lowLatency` the pool never notices that a sound finished, so a
/// player is only handed back when the function returned by `AudioPool.start`
/// is called. This class used to ignore that function: every sound (each
/// scanned item, each approved payment, each failed scan) created a new audio
/// player that was never released. After a few dozen of them the kiosk's main
/// thread was busy even at idle (on a test kiosk: 4% of a core before 60
/// sounds, 93% after) and, on the client's tablet, payments froze for minutes.
/// See [SoundSlot], which ends every sound and caps how many play at once.
class ScanSoundService {
  ScanSoundService._();

  static final SoundSlot _success = SoundSlot(() => _openPort('sounds/success.mp3'));
  static final SoundSlot _failure = SoundSlot(() => _openPort('sounds/failure.mp3'));

  static Future<void> playSuccess() async {
    if (kIsWeb) return;
    try {
      await _success.play();
    } catch (e, st) {
      // Sound is non-critical — never surface audio errors to the user,
      // but never swallow them silently either; this is the only signal
      // we have without a device attached.
      debugPrint('ScanSoundService.playSuccess failed: $e\n$st');
    }
  }

  static Future<void> playFailure() async {
    if (kIsWeb) return;
    try {
      await _failure.play();
    } catch (e, st) {
      debugPrint('ScanSoundService.playFailure failed: $e\n$st');
    }
  }

  static Future<SoundPoolPort> _openPort(String assetPath) async {
    final pool = await AudioPool.create(
      source: AssetSource(assetPath),
      maxPlayers: 3,
      playerMode: PlayerMode.lowLatency,
    );
    await pool.getDuration(); // cached, so the first play knows how long to wait
    return _AudioPoolPort(pool);
  }
}

/// What [SoundSlot] needs from a sound pool: start a sound and get back the
/// function that ends it, and how long the sound lasts.
abstract class SoundPoolPort {
  Future<Future<void> Function()> start();
  Future<Duration?> duration();
}

class _AudioPoolPort implements SoundPoolPort {
  _AudioPoolPort(this._pool);
  final AudioPool _pool;

  @override
  Future<Future<void> Function()> start() => _pool.start();

  @override
  Future<Duration?> duration() => _pool.getDuration();
}

/// One sound effect. Plays it, and ALWAYS ends it again once it has finished
/// (its length plus a small margin), which hands the player back to the pool.
/// At most [maxConcurrent] copies play at the same time: a burst of scans can
/// never create an unbounded number of players — the extra beeps are skipped.
class SoundSlot {
  SoundSlot(
    this._open, {
    this.maxConcurrent = 3,
    this.fallbackLength = const Duration(seconds: 3),
    this.margin = const Duration(milliseconds: 300),
  });

  final Future<SoundPoolPort> Function() _open;
  final int maxConcurrent;
  final Duration fallbackLength;
  final Duration margin;

  Future<SoundPoolPort>? _port;
  int _playing = 0;

  /// Sounds started and not yet ended.
  int get playing => _playing;

  Future<void> play() async {
    if (_playing >= maxConcurrent) return; // already enough in the air
    _playing++;
    Future<void> Function()? stop;
    try {
      final port = await (_port ??= _open());
      stop = await port.start();
      final length = (await port.duration()) ?? fallbackLength;
      final end = stop;
      Timer(length + margin, () {
        end().catchError((Object _) {}).whenComplete(() => _playing--);
      });
    } catch (_) {
      // Opening or starting failed: nothing is playing, forget the port so the
      // next call opens it afresh, and give back a player that did start.
      _port = null;
      _playing--;
      if (stop != null) unawaited(stop().catchError((Object _) {}));
      rethrow;
    }
  }
}
