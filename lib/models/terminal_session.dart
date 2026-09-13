/// A card-present terminal payment attempt (Geidea USB terminal today).
/// Mirrors backend's `TerminalAttemptView` — `id` is what confirm/cancel
/// target, not the order id.
class TerminalSession {
  final String id;
  final String orderId;
  final double amount;
  final String? currency;
  final String status; // PENDING | CONFIRMED | CANCELLED | TIMEOUT

  const TerminalSession({
    required this.id,
    required this.orderId,
    required this.amount,
    this.currency,
    required this.status,
  });

  factory TerminalSession.fromJson(Map<String, dynamic> json) => TerminalSession(
        id: json['id'] as String,
        orderId: json['orderId'] as String,
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] as String?,
        status: json['status'] as String,
      );
}
