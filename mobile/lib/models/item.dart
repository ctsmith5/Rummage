class Item {
  final String id;
  final String saleId;
  final String name;
  final String description;
  final double price;
  final List<String> imageUrls;
  final String category;
  final DateTime createdAt;

  Item({
    required this.id,
    required this.saleId,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrls,
    required this.category,
    required this.createdAt,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'] as String,
      saleId: json['sale_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      category: json['category'] as String? ?? 'Other',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sale_id': saleId,
      'name': name,
      'description': description,
      'price': price,
      'image_urls': imageUrls,
      'category': category,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Item copyWith({
    String? id,
    String? saleId,
    String? name,
    String? description,
    double? price,
    List<String>? imageUrls,
    String? category,
    DateTime? createdAt,
  }) {
    return Item(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrls: imageUrls ?? this.imageUrls,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get formattedPrice => '\$${price.toStringAsFixed(2)}';
  String get primaryImageUrl => imageUrls.isNotEmpty ? imageUrls.first : '';
}

class CreateItemRequest {
  final String name;
  final String description;
  final double price;
  final List<String> imageUrls;
  final String category;

  CreateItemRequest({
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrls,
    required this.category,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'price': price,
      'image_urls': imageUrls,
      'category': category,
    };
  }
}

class ItemCategory {
  static const List<String> categories = [
    'Furniture',
    'Electronics',
    'Clothing',
    'Books',
    'Toys',
    'Kitchen',
    'Tools',
    'Sports',
    'Decor',
    'Antiques',
    'Other',
  ];
}

