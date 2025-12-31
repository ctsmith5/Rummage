import 'package:flutter/foundation.dart';

import '../models/favorite.dart';
import 'api_client.dart';

class FavoriteService extends ChangeNotifier {
  List<Favorite> _favorites = [];
  Set<String> _favoritedSaleIds = {};
  bool _isLoading = false;
  String? _error;

  List<Favorite> get favorites => _favorites;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool isFavorited(String saleId) => _favoritedSaleIds.contains(saleId);

  Future<void> loadFavorites() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiClient.get('/favorites');
      final data = response['data'] as List<dynamic>?;
      _favorites = data?.map((e) => Favorite.fromJson(e)).toList() ?? [];
      _favoritedSaleIds = _favorites.map((f) => f.saleId).toSet();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load favorites';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addFavorite(String saleId) async {
    try {
      final response = await ApiClient.post('/sales/$saleId/favorite');
      final favorite = Favorite.fromJson(response['data']);
      _favorites.add(favorite);
      _favoritedSaleIds.add(saleId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add favorite';
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeFavorite(String saleId) async {
    try {
      await ApiClient.delete('/sales/$saleId/favorite');
      _favorites.removeWhere((f) => f.saleId == saleId);
      _favoritedSaleIds.remove(saleId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to remove favorite';
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleFavorite(String saleId) async {
    if (isFavorited(saleId)) {
      return await removeFavorite(saleId);
    } else {
      return await addFavorite(saleId);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

