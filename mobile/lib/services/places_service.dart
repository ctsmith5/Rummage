import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Model for a place autocomplete prediction
class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structuredFormatting = json['structured_formatting'] as Map<String, dynamic>?;
    return PlacePrediction(
      placeId: json['place_id'] as String,
      description: json['description'] as String,
      mainText: structuredFormatting?['main_text'] as String? ?? '',
      secondaryText: structuredFormatting?['secondary_text'] as String? ?? '',
    );
  }
}

/// Model for place details (coordinates)
class PlaceDetails {
  final String address;
  final double latitude;
  final double longitude;

  PlaceDetails({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

/// Service for Google Places API autocomplete functionality
class PlacesService {
  // Using the same API key as Google Maps
  static const String _apiKey = 'AIzaSyDydUnntQZRFgD6ywh4mdKWCGWGdsDONjE';
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/place';

  /// Get autocomplete predictions for an input string
  static Future<List<PlacePrediction>> getAutocompletePredictions(
    String input, {
    String? sessionToken,
    double? latitude,
    double? longitude,
    int radiusMeters = 50000, // 50km default radius
  }) async {
    if (input.isEmpty) return [];

    try {
      final queryParams = {
        'input': input,
        'key': _apiKey,
        'types': 'address', // Focus on addresses
      };

      // Add location bias if coordinates provided
      if (latitude != null && longitude != null) {
        queryParams['location'] = '$latitude,$longitude';
        queryParams['radius'] = radiusMeters.toString();
      }

      // Add session token if provided (for billing optimization)
      if (sessionToken != null) {
        queryParams['sessiontoken'] = sessionToken;
      }

      final uri = Uri.parse('$_baseUrl/autocomplete/json').replace(
        queryParameters: queryParams,
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'] as String;

        if (status == 'OK') {
          final predictions = data['predictions'] as List<dynamic>;
          return predictions
              .map((p) => PlacePrediction.fromJson(p as Map<String, dynamic>))
              .toList();
        } else if (status == 'ZERO_RESULTS') {
          return [];
        } else {
          debugPrint('Places API error: $status');
          return [];
        }
      } else {
        debugPrint('Places API HTTP error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Places autocomplete error: $e');
      return [];
    }
  }

  /// Get place details (coordinates) for a place ID
  static Future<PlaceDetails?> getPlaceDetails(
    String placeId, {
    String? sessionToken,
  }) async {
    try {
      final queryParams = {
        'place_id': placeId,
        'key': _apiKey,
        'fields': 'formatted_address,geometry',
      };

      if (sessionToken != null) {
        queryParams['sessiontoken'] = sessionToken;
      }

      final uri = Uri.parse('$_baseUrl/details/json').replace(
        queryParameters: queryParams,
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'] as String;

        if (status == 'OK') {
          final result = data['result'] as Map<String, dynamic>;
          final geometry = result['geometry'] as Map<String, dynamic>;
          final location = geometry['location'] as Map<String, dynamic>;

          return PlaceDetails(
            address: result['formatted_address'] as String,
            latitude: (location['lat'] as num).toDouble(),
            longitude: (location['lng'] as num).toDouble(),
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('Places details error: $e');
      return null;
    }
  }

  /// Generate a session token for grouping autocomplete requests
  static String generateSessionToken() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

