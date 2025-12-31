import 'package:flutter/foundation.dart';

import '../models/garage_sale.dart';
import '../models/item.dart';
import 'api_client.dart';

class SalesService extends ChangeNotifier {
  List<GarageSale> _sales = [];
  GarageSale? _selectedSale;
  bool _isLoading = false;
  String? _error;

  List<GarageSale> get sales => _sales;
  GarageSale? get selectedSale => _selectedSale;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadNearbySales(double lat, double lng, {double radius = 10}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiClient.get(
        '/sales',
        queryParams: {
          'lat': lat.toString(),
          'lng': lng.toString(),
          'radius': radius.toString(),
        },
      );

      final data = response['data'] as List<dynamic>?;
      _sales = data?.map((e) => GarageSale.fromJson(e)).toList() ?? [];
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load sales';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<GarageSale?> getSaleDetails(String saleId) async {
    try {
      final response = await ApiClient.get('/sales/$saleId');
      _selectedSale = GarageSale.fromJson(response['data']);
      notifyListeners();
      return _selectedSale;
    } catch (e) {
      _error = 'Failed to load sale details';
      notifyListeners();
      return null;
    }
  }

  Future<GarageSale?> createSale(CreateSaleRequest request) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiClient.post('/sales', body: request.toJson());
      final sale = GarageSale.fromJson(response['data']);
      _sales.add(sale);
      _isLoading = false;
      notifyListeners();
      return sale;
    } catch (e) {
      _error = 'Failed to create sale';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateSale(String saleId, CreateSaleRequest request) async {
    try {
      await ApiClient.put('/sales/$saleId', body: request.toJson());
      await loadNearbySales(0, 0); // Reload sales
      return true;
    } catch (e) {
      _error = 'Failed to update sale';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSale(String saleId) async {
    try {
      await ApiClient.delete('/sales/$saleId');
      _sales.removeWhere((s) => s.id == saleId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete sale';
      notifyListeners();
      return false;
    }
  }

  Future<GarageSale?> startSale(String saleId) async {
    try {
      final response = await ApiClient.post('/sales/$saleId/start');
      final sale = GarageSale.fromJson(response['data']);
      _updateSaleInList(sale);
      return sale;
    } catch (e) {
      _error = 'Failed to start sale';
      notifyListeners();
      return null;
    }
  }

  Future<GarageSale?> endSale(String saleId) async {
    try {
      final response = await ApiClient.post('/sales/$saleId/end');
      final sale = GarageSale.fromJson(response['data']);
      _updateSaleInList(sale);
      return sale;
    } catch (e) {
      _error = 'Failed to end sale';
      notifyListeners();
      return null;
    }
  }

  Future<Item?> addItem(String saleId, CreateItemRequest request) async {
    try {
      final response = await ApiClient.post(
        '/sales/$saleId/items',
        body: request.toJson(),
      );
      final item = Item.fromJson(response['data']);
      
      // Update the selected sale with the new item
      if (_selectedSale?.id == saleId) {
        final updatedItems = [..._selectedSale!.items, item];
        _selectedSale = _selectedSale!.copyWith(items: updatedItems);
        notifyListeners();
      }
      
      return item;
    } catch (e) {
      _error = 'Failed to add item';
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteItem(String saleId, String itemId) async {
    try {
      await ApiClient.delete('/sales/$saleId/items/$itemId');
      
      // Update the selected sale
      if (_selectedSale?.id == saleId) {
        final updatedItems = _selectedSale!.items.where((i) => i.id != itemId).toList();
        _selectedSale = _selectedSale!.copyWith(items: updatedItems);
        notifyListeners();
      }
      
      return true;
    } catch (e) {
      _error = 'Failed to delete item';
      notifyListeners();
      return false;
    }
  }

  void _updateSaleInList(GarageSale updatedSale) {
    final index = _sales.indexWhere((s) => s.id == updatedSale.id);
    if (index != -1) {
      _sales[index] = updatedSale;
    }
    if (_selectedSale?.id == updatedSale.id) {
      _selectedSale = updatedSale;
    }
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

