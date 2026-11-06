import 'decimal.dart';

/// One cart line as priced locally. [unitPrice] is the price EXCLUDING VAT
/// from the pulled product (not priceWithVat).
class PricingInput {
  final int productId;
  final int quantity;
  final String unitPrice;
  const PricingInput(this.productId, this.quantity, this.unitPrice);
}

class PricedLine {
  final int lineNo;
  final int productId;
  final int quantity;
  final String unitPrice;
  final String net; // 2 places
  final String tax; // 2 places
  const PricedLine(this.lineNo, this.productId, this.quantity, this.unitPrice,
      this.net, this.tax);
}

class PricedCart {
  final List<PricedLine> lines;
  final String subtotal;
  final String tax;
  final String total;
  const PricedCart(this.lines, this.subtotal, this.tax, this.total);
}

/// Local pricing, offline.md section 5: net = unit price x quantity, tax per
/// line = net x VAT rate rounded half-up to 2 places, subtotal = sum of line
/// nets, tax = sum of line taxes, total = subtotal + tax. Lines add up to the
/// total exactly. No offers or coupons.
PricedCart priceCart(List<PricingInput> items, {required String vatRate}) {
  if (items.isEmpty) throw ArgumentError('Cannot price an empty cart');
  final rate = Dec.parse(vatRate);
  var subtotal = Dec.fromInt(0).roundHalfUp(2);
  var tax = Dec.fromInt(0).roundHalfUp(2);
  final lines = <PricedLine>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    if (it.quantity < 1) throw ArgumentError('Quantity must be at least 1');
    final net = (Dec.parse(it.unitPrice) * Dec.fromInt(it.quantity)).roundHalfUp(2);
    final lineTax = (net * rate).roundHalfUp(2);
    subtotal = subtotal + net;
    tax = tax + lineTax;
    lines.add(PricedLine(i + 1, it.productId, it.quantity, it.unitPrice,
        net.toFixed(2), lineTax.toFixed(2)));
  }
  final total = subtotal + tax;
  return PricedCart(lines, subtotal.toFixed(2), tax.toFixed(2), total.toFixed(2));
}
