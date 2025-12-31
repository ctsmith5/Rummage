class Favorite {
  final String id;
  final String saleId;
  final DateTime createdAt;

  Favorite({
    required this.id,
    required this.saleId,
    required this.createdAt,
  });

  factory Favorite.fromJson(Map<String, dynamic> json) {
    return Favorite(
      id: json['id'] as String,
      saleId: json['sale_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sale_id': saleId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

