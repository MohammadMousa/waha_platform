class Product {
  final int id;
  final String barcode;
  final Map<String, dynamic> name; // {"ar": "...", "en": "..."}
  final Map<String, dynamic>? description;
  final double price;
  final bool active;
  final int? scopeStoreId;
  final bool publicListed;
  final int? categoryId;
  final int? imageResourceId;

  const Product({
    required this.id,
    required this.barcode,
    required this.name,
    this.description,
    required this.price,
    required this.active,
    this.scopeStoreId,
    this.publicListed = true,
    this.categoryId,
    this.imageResourceId,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as int,
        barcode: json['barcode'] as String,
        name: (json['name'] as Map<String, dynamic>?) ?? {},
        description: json['description'] as Map<String, dynamic>?,
        price: (json['price'] as num).toDouble(),
        active: json['active'] as bool? ?? true,
        scopeStoreId: json['scopeStoreId'] as int?,
        publicListed: json['publicListed'] as bool? ?? true,
        categoryId: json['categoryId'] as int?,
        imageResourceId: json['imageResourceId'] as int?,
      );
}
