import 'product.dart';

class ProductPage {
  final List<Product> products;
  final int page;
  final int size;
  final bool hasMore;

  const ProductPage({
    required this.products,
    required this.page,
    required this.size,
    required this.hasMore,
  });

  factory ProductPage.fromJson(Map<String, dynamic> json) => ProductPage(
        products: (json['products'] as List<dynamic>? ?? [])
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList(),
        page: json['page'] as int? ?? 0,
        size: json['size'] as int? ?? 0,
        hasMore: json['hasMore'] as bool? ?? false,
      );
}
