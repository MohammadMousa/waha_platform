import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

// Plays short programmatic beep tones on scan events.
// WAV bytes are generated at runtime and written to a temp file so
// DeviceFileSource is used — BytesSource is unreliable on Android.
class ScanSoundService {
  ScanSoundService._();

  static final AudioPlayer _player = AudioPlayer();

  // High clean beep — item found and added.
  static Future<void> playSuccess() => _play(880, 0.12);

  // Low descending double-buzz — item not found or not sellable.
  static Future<void> playFailure() async {
    await _play(300, 0.10);
    await Future.delayed(const Duration(milliseconds: 60));
    await _play(220, 0.12);
  }

  static Future<void> _play(int frequencyHz, double durationSec) async {
    try {
      final bytes = _wav(frequencyHz, durationSec);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/waha_beep_$frequencyHz.wav');
      await file.writeAsBytes(bytes, flush: true);
      await _player.play(DeviceFileSource(file.path));
    } catch (_) {
      // Sound is non-critical — never surface audio errors to the user.
    }
  }

  // Generates a minimal 16-bit mono PCM WAV in memory.
  static Uint8List _wav(int hz, double sec, {double volume = 0.55}) {
    const rate = 22050;
    final samples = (rate * sec).round();
    final dataBytes = samples * 2;
    final buf = ByteData(44 + dataBytes);

    // RIFF header
    _str(buf, 0, 'RIFF');
    buf.setUint32(4, 36 + dataBytes, Endian.little);
    _str(buf, 8, 'WAVE');
    // fmt chunk
    _str(buf, 12, 'fmt ');
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20, 1, Endian.little);       // PCM
    buf.setUint16(22, 1, Endian.little);       // mono
    buf.setUint32(24, rate, Endian.little);
    buf.setUint32(28, rate * 2, Endian.little);
    buf.setUint16(32, 2, Endian.little);
    buf.setUint16(34, 16, Endian.little);
    // data chunk
    _str(buf, 36, 'data');
    buf.setUint32(40, dataBytes, Endian.little);

    for (var i = 0; i < samples; i++) {
      final t = i / rate;
      final fadeIn  = math.min(t / (sec * 0.05), 1.0);
      final fadeOut = math.min((sec - t) / (sec * 0.15), 1.0);
      final v = (fadeIn * fadeOut * volume * math.sin(2 * math.pi * hz * t) * 32767)
          .round()
          .clamp(-32768, 32767);
      buf.setInt16(44 + i * 2, v, Endian.little);
    }

    return buf.buffer.asUint8List();
  }

  static void _str(ByteData buf, int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      buf.setUint8(offset + i, s.codeUnitAt(i));
    }
  }
}
