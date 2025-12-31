class Item {
  final String id;
  final String saleId;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String category;
  final DateTime createdAt;

  Item({
    required this.id,
    required this.saleId,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
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
      imageUrl: json['image_url'] as String? ?? '',
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
      'image_url': imageUrl,
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
    String? imageUrl,
    String? category,
    DateTime? createdAt,
  }) {
    return Item(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get formattedPrice => '\$${price.toStringAsFixed(2)}';
}

class CreateItemRequest {
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String category;

  CreateItemRequest({
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.category,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
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

