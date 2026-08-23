/// A line in the in-memory cart. Deliberately has no price on it — price is
/// always what the last /quote response said, never computed on-device.
class CartItem {
  final int productId;
  final String name;
  final int? imageResourceId;
  int quantity;

  CartItem({
    required this.productId,
    required this.name,
    required this.quantity,
    this.imageResourceId,
  });

  Map<String, dynamic> toOrderLine() => {
        'productId': productId,
        'quantity': quantity,
      };
}
