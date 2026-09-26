/// Base class for any non-2xx response. `message` is the backend's own
/// human-readable string — display it or log it, never parse it (there's
/// no error code/enum field per FRONTEND_CONTEXT.md).
sealed class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// 404 on GET /api/products/barcode/{barcode} — unrecognized barcode.
class ProductNotFoundException extends ApiException {
  const ProductNotFoundException(super.statusCode, super.message);
}

/// 409 — product exists but isn't currently sellable. Can happen at scan
/// time, or again at /quote or /orders time if it changed sellability
/// between scan and checkout.
class ProductNotSellableException extends ApiException {
  const ProductNotSellableException(super.statusCode, super.message);
}

/// 404 on GET/POST against an order id that doesn't exist.
class OrderNotFoundException extends ApiException {
  const OrderNotFoundException(super.statusCode, super.message);
}

/// 409 on /pay — already paid, or lost a concurrent-pay race.
class OrderAlreadyPaidException extends ApiException {
  const OrderAlreadyPaidException(super.statusCode, super.message);
}

/// 401 — missing/invalid/expired session token, or bad login credentials.
/// Same status for "wrong password" and "token expired" — the backend
/// doc is explicit these aren't meant to be told apart in the UI.
class UnauthorizedException extends ApiException {
  const UnauthorizedException(super.statusCode, super.message);
}

/// Login rejected because the credentials are wrong (401, code
/// INVALID_CREDENTIALS) — carries how many tries are left before the lock, when
/// the backend says so.
class InvalidCredentialsException extends UnauthorizedException {
  final int? attemptsRemaining;
  final int? maxAttempts;
  const InvalidCredentialsException(super.statusCode, super.message,
      {this.attemptsRemaining, this.maxAttempts});
}

/// Login refused because the account/device is locked (429/423, code
/// ACCOUNT_LOCKED) — not a wrong-PIN answer, and trying again before
/// [retryAfterSeconds] only extends the wait on some servers.
class AccountLockedException extends ApiException {
  final int? retryAfterSeconds;

  /// ACCOUNT_LOCKED, or TOO_MANY_REQUESTS when the whole network address is
  /// being throttled (then the backend's own message is the one to show).
  final String? code;
  const AccountLockedException(super.statusCode, super.message,
      {this.retryAfterSeconds, this.code});

  bool get isIpThrottle => code == 'TOO_MANY_REQUESTS';

  /// Headline for the banner, without the countdown.
  String get headline =>
      isIpThrottle ? message : 'Account temporarily locked.';
}

/// One line for a failed login, for screens that just show text.
String loginFailureText(ApiException e) {
  if (e is AccountLockedException) {
    final s = e.retryAfterSeconds;
    return s == null
        ? (e.isIpThrottle ? e.message : '${e.headline} Try again later.')
        : '${e.headline} Try again in ${formatMmSs(s)}';
  }
  if (e is InvalidCredentialsException && e.attemptsRemaining != null) {
    final n = e.attemptsRemaining!;
    return 'Invalid credentials. $n attempt${n == 1 ? '' : 's'} remaining '
        'before temporary lock.';
  }
  return e.message;
}

/// 299 -> "04:59".
String formatMmSs(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final m = (s ~/ 60).toString().padLeft(2, '0');
  final r = (s % 60).toString().padLeft(2, '0');
  return '$m:$r';
}

/// 409 on register — username already taken.
class UsernameTakenException extends ApiException {
  const UsernameTakenException(super.statusCode, super.message);
}

/// Any other non-2xx we didn't specifically anticipate — still carries the
/// real message, just not a status we've special-cased yet.
class UnknownApiException extends ApiException {
  const UnknownApiException(super.statusCode, super.message);
}

/// Network-level failure (no response at all) — distinct from the above,
/// since this is what checkout's "retry with the same UUID" path is for.
class NetworkException implements Exception {
  final Object cause;
  const NetworkException(this.cause);

  @override
  String toString() => 'Network error: $cause';
}
