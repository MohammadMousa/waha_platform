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
  /// Gallery images (additional product photos beyond the avatar).
  /// Populated from GET /api/products/{id} — empty on list responses.
  final List<int> imageResourceIds;

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
    this.imageResourceIds = const [],
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
        imageResourceIds: (json['imageResourceIds'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
      );

  Product copyWith({
    Map<String, dynamic>? name,
    Map<String, dynamic>? description,
    double? price,
    bool? active,
    bool? publicListed,
    int? categoryId,
    int? imageResourceId,
    bool clearAvatar = false,
    List<int>? imageResourceIds,
  }) =>
      Product(
        id: id,
        barcode: barcode,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        active: active ?? this.active,
        scopeStoreId: scopeStoreId,
        publicListed: publicListed ?? this.publicListed,
        categoryId: categoryId ?? this.categoryId,
        imageResourceId: clearAvatar ? null : (imageResourceId ?? this.imageResourceId),
        imageResourceIds: imageResourceIds ?? this.imageResourceIds,
      );
}
