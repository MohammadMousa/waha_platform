class QuoteLine {
  final int productId;
  final Map<String, dynamic> name; // {"ar": "...", "en": "..."}
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const QuoteLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory QuoteLine.fromJson(Map<String, dynamic> json) => QuoteLine(
        productId: json['productId'] as int,
        name: (json['name'] as Map<String, dynamic>?) ?? {},
        quantity: json['quantity'] as int,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        lineTotal: (json['lineTotal'] as num).toDouble(),
      );
}

class Quote {
  final double subtotal;
  final double tax;
  final double total;
  final List<QuoteLine> items;

  const Quote({
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.items,
  });

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        subtotal: (json['subtotal'] as num).toDouble(),
        tax: (json['tax'] as num).toDouble(),
        total: (json['total'] as num).toDouble(),
        items: (json['items'] as List<dynamic>)
            .map((e) => QuoteLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
