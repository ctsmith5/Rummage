import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'api_client.dart';

class AuthService extends ChangeNotifier {
  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  String? get error => _error;

  Future<void> checkAuthStatus() async {
    try {
      final token = await ApiClient.getToken();
      if (token != null) {
        await getProfile();
      }
    } catch (e) {
      // Handle network/API errors gracefully
      print('Auth check failed: $e');
      _currentUser = null;
      await ApiClient.clearToken();
    }
  }

  Future<bool> register(String email, String password, String name) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiClient.post(
        '/auth/register',
        body: {
          'email': email,
          'password': password,
          'name': name,
        },
        auth: false,
      );

      final authResponse = AuthResponse.fromJson(response['data']);
      await ApiClient.setToken(authResponse.token);
      _currentUser = authResponse.user;
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Registration failed. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiClient.post(
        '/auth/login',
        body: {
          'email': email,
          'password': password,
        },
        auth: false,
      );

      final authResponse = AuthResponse.fromJson(response['data']);
      await ApiClient.setToken(authResponse.token);
      _currentUser = authResponse.user;
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Login failed. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> getProfile() async {
    try {
      final response = await ApiClient.get('/auth/profile');
      _currentUser = User.fromJson(response['data']);
      notifyListeners();
    } catch (e) {
      await logout();
    }
  }

  Future<void> logout() async {
    await ApiClient.clearToken();
    _currentUser = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

