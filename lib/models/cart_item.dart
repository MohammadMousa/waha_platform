/// A line in the in-memory cart. Deliberately has no price on it — price is
/// always what the last /quote response said, never computed on-device.
class CartItem {
  final int productId;
  // Bilingual, like Product.name ({"ar": "...", "en": "..."}) — resolved
  // live at render time via localeName(), not baked into a flat string at
  // add-to-cart time. Baking it in meant switching the app language later
  // couldn't re-resolve a name that was never kept.
  final Map<String, dynamic> name;
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
