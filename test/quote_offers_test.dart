import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/models/quote.dart';

void main() {
  test('a quote from an older backend has no discount', () {
    final q = Quote.fromJson({
      'subtotal': 10.0,
      'tax': 1.5,
      'total': 11.5,
      'items': [
        {
          'productId': 1,
          'name': {'en': 'Water'},
          'quantity': 1,
          'unitPrice': 10.0,
          'lineTotal': 10.0,
        }
      ],
    });
    expect(q.discountAmount, 0);
    expect(q.invoiceOffer, isNull);
    expect(q.items.single.discountAmount, 0);
    expect(q.items.single.offer, isNull);
  });

  test('offer fields are read as the server sends them', () {
    final q = Quote.fromJson({
      'subtotal': 18.0,
      'tax': 2.7,
      'total': 20.7,
      'discountAmount': 7.0,
      'invoiceOffer': {'id': 2, 'name': 'Ten percent'},
      'items': [
        {
          'productId': 2,
          'name': {'en': 'Cola'},
          'quantity': 2,
          'unitPrice': 15.0,
          'lineTotal': 30.0,
          'discountAmount': 7.0,
          'netAmount': 23.0,
          'taxAmount': 3.45,
          'offer': {'id': 1, 'name': 'Cola deal'},
        }
      ],
    });
    expect(q.discountAmount, 7.0);
    expect(q.invoiceOffer!.name, 'Ten percent');
    expect(q.items.single.discountAmount, 7.0);
    expect(q.items.single.offer!.name, 'Cola deal');
    expect(q.total, 20.7);
  });
}
