class CategoryModel {
  final int id;
  final String name;
  final String? description;
  final double price;
  final String emoji;
  final int isActive;
  final int stock;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.emoji,
    required this.isActive,
    this.stock = 0,
  });

  factory CategoryModel.fromMap(Map<String, Object?> map) {
    return CategoryModel(
      id: map['id'] as int,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      emoji: map['emoji'] as String? ?? '🔑',
      isActive: map['is_active'] as int? ?? 1,
      stock: map['stock'] as int? ?? 0,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'emoji': emoji,
      'is_active': isActive,
      'stock': stock,
    };
  }
}
