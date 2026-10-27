/// One money format for the cart: amount with two decimals and the
/// currency symbol where one is known, otherwise the currency code.
String formatMoney(double amount, String? currency) {
  final s = amount.toStringAsFixed(2);
  if (currency == null) return s;
  final u = currency.toUpperCase();
  if (u == 'SAR') return '$s ﷼';
  if (u == 'USD') return '\$$s';
  if (u == 'EUR') return '€$s';
  return '$s $currency';
}
