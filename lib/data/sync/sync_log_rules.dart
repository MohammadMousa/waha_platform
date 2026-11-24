/// When the sync writes a line to the device log.
///
/// At the Info level every attempt is written. At Warn and Error a pull is
/// written only when it brought rows, failed, or is the first successful one
/// since the app started (so a sync that runs but finds nothing still shows
/// that it runs, once per start). Failures and server answers such as "busy"
/// or "401" are always written by their own lines.
class SyncLogRules {
  SyncLogRules._();

  /// The "<feed> up to date (N rows)" line.
  static bool logFeed({required bool detailed, required int rows}) => detailed || rows > 0;

  /// The one-line summary of a finished pull.
  static bool logPullSummary({
    required bool detailed,
    required int rows,
    required bool failed,
    required bool firstOkSinceStart,
  }) =>
      detailed || rows > 0 || failed || firstOkSinceStart;
}
