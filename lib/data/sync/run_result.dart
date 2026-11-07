/// How one manual or scheduled run (a pull or a send) ended, so Settings can
/// tell the person what happened instead of staying silent.
enum RunKind {
  done,
  failed,
  noSession,
  customerActive,
  busy,
  serverBusy,
  authStopped,
}

class RunResult {
  const RunResult(
    this.kind, {
    this.count = 0,
    this.rejected = 0,
    this.detail,
    this.waitSeconds = 0,
  });

  final RunKind kind;

  /// Rows updated (pull) or orders accepted (send).
  final int count;

  /// Orders the server refused for good (send only).
  final int rejected;

  /// Short error text for [RunKind.failed].
  final String? detail;

  /// Seconds the server asked to wait for [RunKind.serverBusy].
  final int waitSeconds;
}
