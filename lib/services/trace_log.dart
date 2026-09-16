import 'package:flutter/services.dart';

/// Diagnostic-only, temporary: forwards Dart-side trace/error text into the
/// SAME native waha_trace.log that MainActivity.logTrace() writes to (see
/// MainActivity.kt and CrashLogActivity.kt) — one file, one "Waha Startup
/// Log" screen, instead of a second separate log the user has to know to
/// check. Reuses the existing 'com.waha/geidea' channel (channel identity
/// is the string name, not object identity, so a second MethodChannel
/// instance here is fine) rather than adding a new one.
///
/// Gated end-to-end by LocalPrefs.loggingEnabled (false by default) — see
/// that field's doc comment. [log] is cheap to call unconditionally: the
/// native side checks the same flag before writing anything, so callers
/// don't need to check it themselves first.
///
/// Remove once the startup crash is root-caused and fixed, alongside the
/// rest of the trace-logging system.
class TraceLog {
  static const _channel = MethodChannel('com.waha/geidea');

  static Future<void> log(String label) async {
    try {
      await _channel.invokeMethod('logTrace', {'label': label});
    } catch (_) {
      // Best-effort only — never let logging itself throw.
    }
  }

  /// Tells the native side the current effective on/off state, so its own
  /// early onCreate/onStart lines (which fire before Dart code can run,
  /// hence before this call) respect whatever was last known — persisted
  /// natively, so it carries over from the previous launch. Call this once
  /// at startup (see main.dart) and again whenever the Settings toggle
  /// changes.
  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setLoggingEnabled', {'enabled': enabled});
    } catch (_) {
      // Best-effort only.
    }
  }
}
