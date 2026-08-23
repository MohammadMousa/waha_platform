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
