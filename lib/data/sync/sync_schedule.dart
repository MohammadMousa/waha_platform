import 'dart:math';

/// The timing rules that keep many kiosks from calling the server at the same
/// moment (offline.md section 1). Pure functions, so they can be tested with a
/// fixed random source.
class SyncSchedule {
  SyncSchedule._();

  /// `sync_stagger_seconds` is clamped to 30..3600; there is no "off".
  static int clampStagger(int seconds) => seconds < 30 ? 30 : (seconds > 3600 ? 3600 : seconds);

  /// A stable spread of device ids (ids are small consecutive numbers, so they
  /// are mixed before taking the remainder).
  static int mix(int id) {
    var h = (id * 2654435761) & 0xFFFFFFFF;
    h ^= h >> 15;
    return h & 0x7FFFFFFF;
  }

  /// Once per app start: start delay + this device's slot in the stagger
  /// window + a small random jitter (up to 5 s).
  static Duration startDelay({
    required Duration base,
    required int deviceId,
    required int staggerSeconds,
    required Random random,
  }) {
    final slot = mix(deviceId) % clampStagger(staggerSeconds);
    return base + Duration(seconds: slot) + Duration(milliseconds: random.nextInt(5000));
  }

  /// [d] plus up to [fraction] of itself (0.10 for the pull interval, 0.20 for
  /// a failed-order retry).
  static Duration withJitter(Duration d, double fraction, Random random) =>
      d + Duration(milliseconds: (d.inMilliseconds * fraction * random.nextDouble()).round());

  /// When connectivity returns: one pull after a random 0..60 s.
  static Duration reconnectDelay(Random random) =>
      Duration(milliseconds: random.nextInt(60000));

  /// The `Retry-After` header: delta-seconds or an HTTP date. Null if absent
  /// or unreadable. Never longer than one hour.
  static Duration? parseRetryAfter(String? header, {DateTime? now}) {
    if (header == null || header.trim().isEmpty) return null;
    final secs = int.tryParse(header.trim());
    Duration? d;
    if (secs != null) {
      d = Duration(seconds: secs);
    } else {
      try {
        final at = _parseHttpDate(header.trim());
        d = at.difference((now ?? DateTime.now()).toUtc());
      } catch (_) {
        return null;
      }
    }
    if (d.isNegative) return Duration.zero;
    return d > const Duration(hours: 1) ? const Duration(hours: 1) : d;
  }

  static DateTime _parseHttpDate(String s) {
    // "Wed, 21 Oct 2026 07:28:00 GMT"
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final m = RegExp(r'^\w{3}, (\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$').firstMatch(s);
    if (m == null) throw const FormatException('not an HTTP date');
    return DateTime.utc(int.parse(m[3]!), months.indexOf(m[2]!) + 1, int.parse(m[1]!),
        int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
  }

  /// Status report rule: send when the numbers changed (at most once a
  /// minute), otherwise about every ten minutes.
  static bool shouldSendStatus({
    required bool changed,
    required Duration sinceLastSend,
  }) {
    if (sinceLastSend < const Duration(minutes: 1)) return false;
    return changed || sinceLastSend >= const Duration(minutes: 10);
  }
}
