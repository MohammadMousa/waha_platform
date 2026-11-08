/// The server's `offline_mode` property. A string with three values:
///  - off:     online only (as before),
///  - caching: reads and orders go to the server first, every good read is
///             saved locally, the local copy is used only when the server
///             cannot be reached; no scheduled pull,
///  - full:    the whole catalog is pulled and sales are local-first.
/// The old true/false are still understood (true = full, false = off), so a
/// device saved before this change keeps working.
enum OfflineLevel {
  off,
  caching,
  full;

  /// Any unknown or missing value is [off]: the safe, online behaviour.
  static OfflineLevel parse(String? v) {
    switch ((v ?? '').trim().toLowerCase()) {
      case 'full':
      case 'true':
        return OfflineLevel.full;
      case 'caching':
        return OfflineLevel.caching;
      default:
        return OfflineLevel.off;
    }
  }
}
