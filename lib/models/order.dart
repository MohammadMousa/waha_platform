import 'quote.dart';

/// Returned by POST /api/orders, GET /api/orders/{id}, GET /api/orders,
/// and nested inside the /pay response.
class WahaOrder {
  final String orderId;
  final bool? wasCreated;
  final String status; // CREATED | PAID | FAILED
  final double subtotal;
  final double tax;
  final double total;
  final double? taxRate;
  final String? currency;
  final String? paymentReference;
  final String? paymentMethod; // provider key of the most recent successful payment: stripe/simulated/etc
  final String? username;
  final String? invoiceUrl;
  final int? displayId; // human-readable order number, per-store sequential
  /// What the customer was shown when the server had not numbered the order
  /// yet (orders made offline), e.g. WH-01-0233.
  final String? orderReference;
  final int? storeId;
  final String? createdAt;
  final List<QuoteLine> items;

  /// Total discount from all offers, and the invoice-level offer if any.
  final double discountAmount;
  final AppliedOffer? invoiceOffer;

  /// The number to show: the server's order number when there is one, else
  /// the order reference.
  String? get displayNumber =>
      displayId != null ? '#$displayId' : orderReference;

  const WahaOrder({
    required this.orderId,
    this.wasCreated,
    required this.status,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.taxRate,
    this.currency,
    this.paymentReference,
    this.paymentMethod,
    this.username,
    this.invoiceUrl,
    this.displayId,
    this.orderReference,
    this.storeId,
    this.createdAt,
    required this.items,
    this.discountAmount = 0.0,
    this.invoiceOffer,
  });

  /// The same order with another status (a server order that was paid while
  /// the server could not be told keeps its own lines and numbers).
  WahaOrder withStatus(String newStatus) => WahaOrder(
        orderId: orderId,
        wasCreated: wasCreated,
        status: newStatus,
        subtotal: subtotal,
        tax: tax,
        total: total,
        taxRate: taxRate,
        currency: currency,
        paymentReference: paymentReference,
        paymentMethod: paymentMethod,
        username: username,
        invoiceUrl: invoiceUrl,
        displayId: displayId,
        orderReference: orderReference,
        storeId: storeId,
        createdAt: createdAt,
        items: items,
        discountAmount: discountAmount,
        invoiceOffer: invoiceOffer,
      );

  factory WahaOrder.fromJson(Map<String, dynamic> json) => WahaOrder(
        orderId: json['orderId'] as String,
        wasCreated: json['wasCreated'] as bool?,
        status: json['status'] as String,
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
        tax: (json['tax'] as num?)?.toDouble() ?? 0.0,
        total: (json['total'] as num).toDouble(),
        taxRate: (json['taxRate'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        paymentReference: json['paymentReference'] as String?,
        paymentMethod: json['paymentMethod'] as String?,
        username: json['username'] as String?,
        invoiceUrl: json['invoiceUrl'] as String?,
        displayId: json['displayId'] as int?,
        orderReference: json['orderReference'] as String?,
        storeId: json['storeId'] as int?,
        createdAt: json['createdAt'] as String?,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => QuoteLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
        invoiceOffer: AppliedOffer.fromJson(json['invoiceOffer']),
      );
}
