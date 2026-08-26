/// A payment method available to a store in a given mode.
/// provider: REDIRECT (external URL, browser launch), QR_LINK (external URL shown as QR on kiosk),
///           PAYMENT_URL (invoice URL as QR for mobile handoff, kiosk only),
///           TERMINAL (POS reader), SIMULATED (dev/kiosk mock)
/// offlineCapable: TERMINAL = true (POS has own connectivity), REDIRECT/QR_LINK = false, SIMULATED = true
class PaymentMethod {
  final int id;
  final String key;
  final Map<String, dynamic>? displayName;
  final String provider; // REDIRECT | QR_LINK | PAYMENT_URL | TERMINAL | SIMULATED
  final bool offlineCapable;
  final int sortOrder;
  final String? paymentUrl; // only set for PAYMENT_URL provider

  const PaymentMethod({
    required this.id,
    required this.key,
    required this.displayName,
    required this.provider,
    required this.offlineCapable,
    required this.sortOrder,
    this.paymentUrl,
  });

  bool get isQrLink => provider == 'QR_LINK';
  bool get isPaymentUrl => provider == 'PAYMENT_URL';

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
        id: json['id'] as int,
        key: json['key'] as String,
        displayName: json['displayName'] as Map<String, dynamic>?,
        provider: json['provider'] as String,
        offlineCapable: json['offlineCapable'] as bool? ?? false,
        sortOrder: json['sortOrder'] as int? ?? 0,
        paymentUrl: json['paymentUrl'] as String?,
      );
}
