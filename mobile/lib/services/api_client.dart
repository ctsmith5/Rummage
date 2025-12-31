import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  // Development: Use Cloud Run deployed backend
  // For local testing, change back to: 'http://localhost:8080/api'
  static const String baseUrl = 'https://rummage-backend-287868745320.us-central1.run.app/api';
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  /// Enable/disable verbose logging
  static const bool _enableLogging = true;

  static void _log(String message, {Object? error, StackTrace? stackTrace}) {
    if (_enableLogging) {
      final timestamp = DateTime.now().toIso8601String();
      print('[$timestamp] API: $message');
      if (error != null) {
        print('[$timestamp] API ERROR: $error');
      }
      if (stackTrace != null) {
        print('[$timestamp] STACK TRACE:\n$stackTrace');
      }
      // Also log to developer console for better IDE integration
      developer.log(message, name: 'ApiClient', error: error, stackTrace: stackTrace);
    }
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  static Future<void> setToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
  }

  static Future<Map<String, String>> _getHeaders({bool auth = true}) async {
    final headers = {
      'Content-Type': 'application/json',
    };

    if (auth) {
      final token = await getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  static Future<Map<String, dynamic>> get(
    String endpoint, {
    bool auth = true,
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);
    final headers = await _getHeaders(auth: auth);

    _log('GET $uri');
    
    try {
      final response = await http.get(uri, headers: headers);
      return _handleResponse(response, 'GET', endpoint);
    } catch (e, stackTrace) {
      _log('GET $endpoint failed', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders(auth: auth);

    _log('POST $endpoint');
    _log('Request body: ${body != null ? jsonEncode(body) : 'null'}');

    try {
      final response = await http.post(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      return _handleResponse(response, 'POST', endpoint);
    } catch (e, stackTrace) {
      _log('POST $endpoint failed', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> put(
    String endpoint, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders(auth: auth);

    _log('PUT $endpoint');
    _log('Request body: ${body != null ? jsonEncode(body) : 'null'}');

    try {
      final response = await http.put(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      return _handleResponse(response, 'PUT', endpoint);
    } catch (e, stackTrace) {
      _log('PUT $endpoint failed', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> delete(
    String endpoint, {
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders(auth: auth);

    _log('DELETE $endpoint');

    try {
      final response = await http.delete(uri, headers: headers);
      return _handleResponse(response, 'DELETE', endpoint);
    } catch (e, stackTrace) {
      _log('DELETE $endpoint failed', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  static Map<String, dynamic> _handleResponse(http.Response response, String method, String endpoint) {
    _log('$method $endpoint - Status: ${response.statusCode}');
    _log('Response body: ${response.body}');

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      _log('Failed to parse response as JSON', error: e);
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Invalid response format: ${response.body}',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _log('$method $endpoint - Success');
      return body;
    } else {
      final errorMessage = body['error'] as String? ?? 'An error occurred';
      final validationErrors = body['errors'] as Map<String, dynamic>?;
      
      _log('$method $endpoint - Error: $errorMessage');
      if (validationErrors != null) {
        _log('Validation errors: $validationErrors');
      }
      
      throw ApiException(
        statusCode: response.statusCode,
        message: errorMessage,
        errors: validationErrors,
      );
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? errors;

  ApiException({
    required this.statusCode,
    required this.message,
    this.errors,
  });

  @override
  String toString() {
    final buffer = StringBuffer('ApiException: $message (status: $statusCode)');
    if (errors != null && errors!.isNotEmpty) {
      buffer.write('\nValidation errors: $errors');
    }
    return buffer.toString();
  }
}
