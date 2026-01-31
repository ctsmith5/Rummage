import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../models/public_profile.dart';
import 'api_client.dart';

class ProfileService extends ChangeNotifier {
  Profile? _profile;
  bool _isLoading = false;
  String? _error;

  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadProfile() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await ApiClient.get('/profile');
      _profile = Profile.fromJson(res['data'] as Map<String, dynamic>);
    } catch (e) {
      _error = 'Failed to load profile';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfile({
    String? displayName,
    String? bio,
    DateTime? dob,
    String? photoUrl,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final body = (_profile ??
              Profile(userId: '', displayName: '', bio: '', dob: DateTime(1970), photoUrl: ''))
          .toUpsertJson(
        displayName: displayName,
        bio: bio,
        dob: dob,
        photoUrl: photoUrl,
      );

      final res = await ApiClient.put('/profile', body: body);
      _profile = Profile.fromJson(res['data'] as Map<String, dynamic>);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to update profile';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<List<String>> deleteAccount() async {
    // Returns image URLs to delete from Firebase Storage.
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await ApiClient.delete('/account');
      final data = res['data'] as Map<String, dynamic>? ?? {};
      final urls = (data['image_urls'] as List<dynamic>? ?? []).cast<String>();
      _isLoading = false;
      notifyListeners();
      return urls;
    } catch (e) {
      _error = 'Failed to delete account';
      _isLoading = false;
      notifyListeners();
      return [];
    }
  }

  Future<PublicProfile?> loadPublicProfile(String userId) async {
    try {
      final res = await ApiClient.get('/profile/$userId');
      return PublicProfile.fromJson(res['data'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

