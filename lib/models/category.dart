class Category {
  final int id;
  final Map<String, dynamic> name;
  final int? parentId;
  final int? imageResourceId;

  const Category({
    required this.id,
    required this.name,
    this.parentId,
    this.imageResourceId,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int,
        name: (json['name'] as Map<String, dynamic>?) ?? {},
        parentId: json['parentId'] as int?,
        imageResourceId: json['imageResourceId'] as int?,
      );
}
