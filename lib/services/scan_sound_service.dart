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
class ScanSoundService {
  ScanSoundService._();

  static Future<AudioPool>? _successPool;
  static Future<AudioPool>? _failurePool;

  static Future<void> playSuccess() async {
    debugPrint('TEMP: ScanSoundService.playSuccess() called, kIsWeb=$kIsWeb');
    if (kIsWeb) return;
    try {
      final pool = await (_successPool ??= _buildPool('sounds/success.mp3'));
      await pool.start();
      debugPrint('TEMP: ScanSoundService.playSuccess() pool.start() returned normally');
    } catch (e, st) {
      // Sound is non-critical — never surface audio errors to the user,
      // but never swallow them silently either; this is the only signal
      // we have without a device attached.
      _successPool = null;
      debugPrint('ScanSoundService.playSuccess failed: $e\n$st');
    }
  }

  static Future<void> playFailure() async {
    debugPrint('TEMP: ScanSoundService.playFailure() called, kIsWeb=$kIsWeb');
    if (kIsWeb) return;
    try {
      final pool = await (_failurePool ??= _buildPool('sounds/failure.mp3'));
      await pool.start();
      debugPrint('TEMP: ScanSoundService.playFailure() pool.start() returned normally');
    } catch (e, st) {
      _failurePool = null;
      debugPrint('ScanSoundService.playFailure failed: $e\n$st');
    }
  }

  static Future<AudioPool> _buildPool(String assetPath) {
    return AudioPool.create(
      source: AssetSource(assetPath),
      maxPlayers: 3,
      playerMode: PlayerMode.lowLatency,
    );
  }
}
