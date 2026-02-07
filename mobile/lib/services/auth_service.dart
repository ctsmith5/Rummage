import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../models/user.dart';

class AuthService extends ChangeNotifier {
  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;
  String? get error => _error;

  AuthService() {
    // Keep local state in sync with Firebase auth state.
    _auth.authStateChanges().listen((fb.User? user) {
      _currentUser = _mapFirebaseUser(user);
      notifyListeners();
    });
  }

  User? _mapFirebaseUser(fb.User? user) {
    if (user == null) return null;
    return User(
      id: user.uid,
      email: user.email ?? '',
      name: user.displayName ?? '',
      createdAt: user.metadata.creationTime ?? DateTime.now(),
      emailVerified: user.emailVerified,
    );
  }

  Future<void> checkAuthStatus() async {
    _currentUser = _mapFirebaseUser(_auth.currentUser);
    notifyListeners();
  }

  Future<bool> register(String email, String password, String name) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      await cred.user?.sendEmailVerification();
      await cred.user?.reload();
      _currentUser = _mapFirebaseUser(_auth.currentUser);
      _isLoading = false;
      notifyListeners();
      return true;
    } on fb.FirebaseAuthException catch (e) {
      _error = 'FirebaseAuth (${e.code}): ${e.message ?? 'Registration failed. Please try again.'}';
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
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      _currentUser = _mapFirebaseUser(_auth.currentUser);
      _isLoading = false;
      notifyListeners();
      return true;
    } on fb.FirebaseAuthException catch (e) {
      _error = 'FirebaseAuth (${e.code}): ${e.message ?? 'Login failed. Please try again.'}';
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

  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  Future<bool> sendEmailVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
      return true;
    } catch (e) {
      _error = 'Failed to send verification email. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> checkEmailVerified() async {
    try {
      await _auth.currentUser?.reload();
      _currentUser = _mapFirebaseUser(_auth.currentUser);
      notifyListeners();
      return _auth.currentUser?.emailVerified ?? false;
    } catch (e) {
      _error = 'Failed to check verification status. Please try again.';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

