import 'package:flutter/foundation.dart';

import '../models/garage_sale.dart';
import '../models/item.dart';
import 'api_client.dart';

class SalesService extends ChangeNotifier {
  List<GarageSale> _sales = [];
  GarageSale? _selectedSale;
  bool _isLoading = false;
  String? _error;

  // Persist pins between bounds loads so we don't "forget" previously seen sales
  // when the user pans away and back.
  static const int _maxCachedSales = 500;
  final Map<String, GarageSale> _cacheById = {};
  final Map<String, int> _lastSeenMsById = {};
  _Bounds? _currentBounds;

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
      final loaded = data?.map((e) => GarageSale.fromJson(e)).toList() ?? [];
      _upsertIntoCache(loaded);
      _sales = loaded;
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

  Future<List<GarageSale>> searchNearbySales({
    required double lat,
    required double lng,
    double radius = 10,
    required String query,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return [];
    }

    _isLoading = true;
    _error = null;
    // Clear any previously loaded (bounds/nearby) pins so only search results are visible.
    _sales = [];
    notifyListeners();

    _log('Searching nearby sales: q="$q" lat=$lat, lng=$lng, radius=$radius');

    try {
      final response = await ApiClient.get(
        '/sales/search',
        queryParams: {
          'lat': lat.toString(),
          'lng': lng.toString(),
          'radius': radius.toString(),
          'q': q,
        },
      );

      final data = response['data'] as List<dynamic>?;
      final loaded = data?.map((e) => GarageSale.fromJson(e)).toList() ?? [];
      _upsertIntoCache(loaded);
      _sales = loaded;
      _isLoading = false;
      notifyListeners();
      return loaded;
    } catch (e, stackTrace) {
      _log('Failed to search sales', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return [];
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
    _currentBounds = _Bounds(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
    // Show cached pins immediately for the incoming bounds (prevents "blank" gap).
    _sales = _filterCacheToBounds(_currentBounds!);
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
          'limit': _maxCachedSales.toString(),
        },
      );

      final data = response['data'] as List<dynamic>?;
      final loaded = data?.map((e) => GarageSale.fromJson(e)).toList() ?? [];
      _upsertIntoCache(loaded);
      _sales = _currentBounds != null ? _filterCacheToBounds(_currentBounds!) : loaded;
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

  Future<GarageSale?> setSaleCoverPhoto(String saleId, String coverUrl) async {
    _log('Setting sale cover photo: saleId=$saleId');
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiClient.put(
        '/sales/$saleId/cover',
        body: {
          'sale_cover_photo': coverUrl,
        },
      );

      final updated = GarageSale.fromJson(response['data']);

      // Update selected sale and caches/lists.
      if (_selectedSale?.id == saleId) {
        _selectedSale = updated;
      }
      _cacheById[saleId] = updated;
      final listIdx = _sales.indexWhere((s) => s.id == saleId);
      if (listIdx != -1) {
        _sales[listIdx] = updated;
      }

      _isLoading = false;
      notifyListeners();
      return updated;
    } catch (e, stackTrace) {
      _log('Failed to set sale cover photo', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      _isLoading = false;
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
      _upsertIntoCache([sale]);
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
      _cacheById.remove(saleId);
      _lastSeenMsById.remove(saleId);
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

  Future<Item?> updateItem(String saleId, String itemId, CreateItemRequest request) async {
    _log('Updating item $itemId for sale $saleId');
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiClient.put(
        '/sales/$saleId/items/$itemId',
        body: request.toJson(),
      );
      final updated = Item.fromJson(response['data']);

      if (_selectedSale?.id == saleId) {
        final updatedItems = _selectedSale!.items
            .map((i) => i.id == itemId ? updated : i)
            .toList();
        _selectedSale = _selectedSale!.copyWith(items: updatedItems);
      }

      // Also update any cached/list sales that contain this item (best effort).
      for (final entry in _cacheById.entries) {
        final s = entry.value;
        final idx = s.items.indexWhere((i) => i.id == itemId);
        if (idx != -1) {
          final newItems = [...s.items];
          newItems[idx] = updated;
          _cacheById[entry.key] = s.copyWith(items: newItems);
        }
      }
      final listIdx = _sales.indexWhere((s) => s.id == saleId);
      if (listIdx != -1) {
        final s = _sales[listIdx];
        final idx = s.items.indexWhere((i) => i.id == itemId);
        if (idx != -1) {
          final newItems = [...s.items];
          newItems[idx] = updated;
          _sales[listIdx] = s.copyWith(items: newItems);
        }
      }

      _isLoading = false;
      notifyListeners();
      return updated;
    } catch (e, stackTrace) {
      _log('Failed to update item', error: e, stackTrace: stackTrace);
      _error = _getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return null;
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
    _upsertIntoCache([updatedSale]);
    notifyListeners();
  }

  void _upsertIntoCache(List<GarageSale> sales) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final s in sales) {
      _cacheById[s.id] = s;
      _lastSeenMsById[s.id] = now;
    }

    if (_cacheById.length <= _maxCachedSales) return;

    final entries = _lastSeenMsById.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // oldest first

    var idx = 0;
    while (_cacheById.length > _maxCachedSales && idx < entries.length) {
      final id = entries[idx].key;
      _cacheById.remove(id);
      _lastSeenMsById.remove(id);
      idx++;
    }
  }

  List<GarageSale> _filterCacheToBounds(_Bounds b) {
    final out = <GarageSale>[];
    for (final sale in _cacheById.values) {
      if (sale.latitude >= b.minLat &&
          sale.latitude <= b.maxLat &&
          sale.longitude >= b.minLng &&
          sale.longitude <= b.maxLng) {
        out.add(sale);
      }
    }
    return out;
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

class _Bounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const _Bounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });
}
