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

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] SalesService: $message');
    if (error != null) {
      print('[$timestamp] SalesService ERROR: $error');
      if (error is ApiException) {
        print('[$timestamp] SalesService API Error Details:');
        print('  Status: ${error.statusCode}');
        print('  Message: ${error.message}');
        if (error.errors != null) {
          print('  Validation Errors: ${error.errors}');
        }
      }
    }
    if (stackTrace != null) {
      print('[$timestamp] SalesService STACK TRACE:\n$stackTrace');
    }
  }

  Future<void> loadNearbySales(double lat, double lng, {double radius = 10}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _log('Loading nearby sales: lat=$lat, lng=$lng, radius=$radius');

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
      _log('Loaded ${_sales.length} sales');
      _isLoading = false;
      notifyListeners();
    } catch (e, stackTrace) {
      _log('Failed to load sales', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSalesByBounds({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _log('Loading sales by bounds: minLat=$minLat, maxLat=$maxLat, minLng=$minLng, maxLng=$maxLng');

    try {
      final response = await ApiClient.get(
        '/sales/bounds',
        queryParams: {
          'minLat': minLat.toString(),
          'maxLat': maxLat.toString(),
          'minLng': minLng.toString(),
          'maxLng': maxLng.toString(),
        },
      );

      final data = response['data'] as List<dynamic>?;
      _sales = data?.map((e) => GarageSale.fromJson(e)).toList() ?? [];
      _log('Loaded ${_sales.length} sales within bounds');
      _isLoading = false;
      notifyListeners();
    } catch (e, stackTrace) {
      _log('Failed to load sales by bounds', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<GarageSale?> getSaleDetails(String saleId) async {
    _log('Getting sale details: $saleId');
    
    try {
      final response = await ApiClient.get('/sales/$saleId');
      _selectedSale = GarageSale.fromJson(response['data']);
      _log('Loaded sale details: ${_selectedSale?.title}');
      notifyListeners();
      return _selectedSale;
    } catch (e, stackTrace) {
      _log('Failed to load sale details', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      notifyListeners();
      return null;
    }
  }

  Future<GarageSale?> createSale(CreateSaleRequest request) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _log('Creating sale: ${request.title}');
    _log('Sale data: ${request.toJson()}');

    try {
      final response = await ApiClient.post('/sales', body: request.toJson());
      _log('Create sale response: $response');
      
      final sale = GarageSale.fromJson(response['data']);
      _sales.add(sale);
      _log('Sale created successfully: ${sale.id}');
      _isLoading = false;
      notifyListeners();
      return sale;
    } catch (e, stackTrace) {
      _log('Failed to create sale', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateSale(String saleId, CreateSaleRequest request) async {
    _log('Updating sale: $saleId');
    
    try {
      await ApiClient.put('/sales/$saleId', body: request.toJson());
      _log('Sale updated successfully');
      await loadNearbySales(0, 0); // Reload sales
      return true;
    } catch (e, stackTrace) {
      _log('Failed to update sale', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSale(String saleId) async {
    _log('Deleting sale: $saleId');
    
    try {
      await ApiClient.delete('/sales/$saleId');
      _sales.removeWhere((s) => s.id == saleId);
      _log('Sale deleted successfully');
      notifyListeners();
      return true;
    } catch (e, stackTrace) {
      _log('Failed to delete sale', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<GarageSale?> startSale(String saleId) async {
    _log('Starting sale: $saleId');
    
    try {
      final response = await ApiClient.post('/sales/$saleId/start');
      final sale = GarageSale.fromJson(response['data']);
      _updateSaleInList(sale);
      _log('Sale started successfully');
      return sale;
    } catch (e, stackTrace) {
      _log('Failed to start sale', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      notifyListeners();
      return null;
    }
  }

  Future<GarageSale?> endSale(String saleId) async {
    _log('Ending sale: $saleId');
    
    try {
      final response = await ApiClient.post('/sales/$saleId/end');
      final sale = GarageSale.fromJson(response['data']);
      _updateSaleInList(sale);
      _log('Sale ended successfully');
      return sale;
    } catch (e, stackTrace) {
      _log('Failed to end sale', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      notifyListeners();
      return null;
    }
  }

  Future<Item?> addItem(String saleId, CreateItemRequest request) async {
    _log('Adding item to sale $saleId: ${request.name}');
    
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
      
      _log('Item added successfully: ${item.id}');
      return item;
    } catch (e, stackTrace) {
      _log('Failed to add item', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteItem(String saleId, String itemId) async {
    _log('Deleting item $itemId from sale $saleId');
    
    try {
      await ApiClient.delete('/sales/$saleId/items/$itemId');
      
      // Update the selected sale
      if (_selectedSale?.id == saleId) {
        final updatedItems = _selectedSale!.items.where((i) => i.id != itemId).toList();
        _selectedSale = _selectedSale!.copyWith(items: updatedItems);
        notifyListeners();
      }
      
      _log('Item deleted successfully');
      return true;
    } catch (e, stackTrace) {
      _log('Failed to delete item', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
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

  String _getErrorMessage(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return error.toString();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
