import 'order.dart';

class PayResult {
  final bool paid;
  final String status; // PAID | FAILED
  final String? detail; // e.g. "Simulated decline"
  final WahaOrder order;

  const PayResult({
    required this.paid,
    required this.status,
    this.detail,
    required this.order,
  });

  factory PayResult.fromJson(Map<String, dynamic> json) => PayResult(
        paid: json['paid'] as bool,
        status: json['status'] as String,
        detail: json['detail'] as String?,
        order: WahaOrder.fromJson(json['order'] as Map<String, dynamic>),
      );
}
