import 'item.dart';

class GarageSale {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String address;
  final String saleCoverPhoto;
  final double latitude;
  final double longitude;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final List<Item> items;
  final DateTime createdAt;

  GarageSale({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.address,
    required this.saleCoverPhoto,
    required this.latitude,
    required this.longitude,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.items,
    required this.createdAt,
  });

  factory GarageSale.fromJson(Map<String, dynamic> json) {
    return GarageSale(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      address: json['address'] as String,
      saleCoverPhoto: json['sale_cover_photo'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      // Backend returns RFC3339 timestamps (typically UTC). Convert to device-local
      // so the UI consistently shows the user's local timezone.
      startDate: DateTime.parse(json['start_date'] as String).toLocal(),
      endDate: DateTime.parse(json['end_date'] as String).toLocal(),
      isActive: json['is_active'] as bool? ?? false,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => Item.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'description': description,
      'address': address,
      'sale_cover_photo': saleCoverPhoto,
      'latitude': latitude,
      'longitude': longitude,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'is_active': isActive,
      'items': items.map((e) => e.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  GarageSale copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    String? address,
    String? saleCoverPhoto,
    double? latitude,
    double? longitude,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
    List<Item>? items,
    DateTime? createdAt,
  }) {
    return GarageSale(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      address: address ?? this.address,
      saleCoverPhoto: saleCoverPhoto ?? this.saleCoverPhoto,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Calculate distance from given coordinates (in miles)
  double distanceFrom(double lat, double lng) {
    const double earthRadiusMiles = 3959.0;
    final double lat1Rad = latitude * 3.14159265359 / 180;
    final double lat2Rad = lat * 3.14159265359 / 180;
    final double deltaLat = (lat - latitude) * 3.14159265359 / 180;
    final double deltaLon = (lng - longitude) * 3.14159265359 / 180;

    final double a = _sin(deltaLat / 2) * _sin(deltaLat / 2) +
        _cos(lat1Rad) * _cos(lat2Rad) * _sin(deltaLon / 2) * _sin(deltaLon / 2);
    final double c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));

    return earthRadiusMiles * c;
  }

  // Simple math helpers (avoid importing dart:math for this)
  double _sin(double x) => x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  double _cos(double x) => 1 - (x * x) / 2 + (x * x * x * x) / 24;
  double _sqrt(double x) {
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
  double _atan2(double y, double x) => y / (x + 0.0001); // Simplified
}

class CreateSaleRequest {
  final String title;
  final String description;
  final String address;
  final double latitude;
  final double longitude;
  final DateTime startDate;
  final DateTime endDate;

  CreateSaleRequest({
    required this.title,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.startDate,
    required this.endDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'start_date': startDate.toUtc().toIso8601String(),
      'end_date': endDate.toUtc().toIso8601String(),
    };
  }
}

