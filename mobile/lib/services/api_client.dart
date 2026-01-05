import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  // Live (Cloud Run) backend
  static const String baseUrl =
      'https://rummage-backend-287868745320.us-central1.run.app/api';

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

  static Future<String?> _getFirebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      // Force refresh to avoid edge cases where a cached token is expired/revoked.
      return await user.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      _log('Failed to get Firebase ID token (${e.code})', error: e);
      // If the local credential/session is no longer valid, force a clean re-login.
      if (e.code == 'user-token-expired' ||
          e.code == 'invalid-user-token' ||
          e.code == 'user-disabled' ||
          e.code == 'requires-recent-login') {
        await FirebaseAuth.instance.signOut();
      }
      return null;
    } catch (e) {
      _log('Failed to get Firebase ID token', error: e);
      return null;
    }
  }

  static Future<Map<String, String>> _getHeaders({bool auth = true}) async {
    final headers = {
      'Content-Type': 'application/json',
    };

    if (auth) {
      final token = await _getFirebaseIdToken();
      if (token == null) {
        throw ApiException(statusCode: 401, message: 'Not authenticated');
      }
      headers['Authorization'] = 'Bearer $token';
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
      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response, 'GET', endpoint);
    } catch (e, stackTrace) {
      _log('GET $endpoint failed', error: e, stackTrace: stackTrace);
      throw ApiException(
        statusCode: 0,
        message: 'Network error: Unable to connect to server',
      );
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
      ).timeout(const Duration(seconds: 10));
      return _handleResponse(response, 'POST', endpoint);
    } catch (e, stackTrace) {
      _log('POST $endpoint failed', error: e, stackTrace: stackTrace);
      throw ApiException(
        statusCode: 0,
        message: 'Network error: Unable to connect to server',
      );
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
