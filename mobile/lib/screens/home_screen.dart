import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/garage_sale.dart';
import '../services/auth_service.dart';
import '../services/sales_service.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../widgets/map_pin_card.dart';
import '../widgets/sale_map.dart';
import 'saved_screen.dart';
import 'sale_details_screen.dart';
import 'create_sale_screen.dart';
import 'auth/login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  GarageSale? _selectedSale;
  Timer? _boundsDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final locationService = context.read<LocationService>();
    await locationService.getCurrentLocation();

    if (locationService.hasLocation) {
      final salesService = context.read<SalesService>();
      await salesService.loadNearbySales(
        locationService.latitude,
        locationService.longitude,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _boundsDebounce?.cancel();
    super.dispose();
  }

  MapBounds? _lastBounds;
  bool _isInitialBoundsLoad = true;
  
  void _onMapBoundsChanged(MapBounds bounds) {
    // Skip initial bounds load - we already loaded nearby sales in _loadData
    if (_isInitialBoundsLoad) {
      _isInitialBoundsLoad = false;
      _lastBounds = bounds;
      return;
    }
    
    // Skip if bounds haven't changed significantly (avoid unnecessary API calls)
    if (_lastBounds != null) {
      // Calculate center of bounds
      final oldCenterLat = (_lastBounds!.minLat + _lastBounds!.maxLat) / 2;
      final oldCenterLng = (_lastBounds!.minLng + _lastBounds!.maxLng) / 2;
      final newCenterLat = (bounds.minLat + bounds.maxLat) / 2;
      final newCenterLng = (bounds.minLng + bounds.maxLng) / 2;
      
      // Calculate span (size) of bounds
      final oldLatSpan = _lastBounds!.maxLat - _lastBounds!.minLat;
      final oldLngSpan = _lastBounds!.maxLng - _lastBounds!.minLng;
      final newLatSpan = bounds.maxLat - bounds.minLat;
      final newLngSpan = bounds.maxLng - bounds.minLng;
      
      // Check if center moved significantly (more than 5% of span) or zoom changed (more than 10% span change)
      final centerLatDiff = (newCenterLat - oldCenterLat).abs();
      final centerLngDiff = (newCenterLng - oldCenterLng).abs();
      final latSpanDiff = (newLatSpan - oldLatSpan).abs() / oldLatSpan;
      final lngSpanDiff = (newLngSpan - oldLngSpan).abs() / oldLngSpan;
      
      // Only update if bounds changed significantly
      if (centerLatDiff < oldLatSpan * 0.05 && 
          centerLngDiff < oldLngSpan * 0.05 && 
          latSpanDiff < 0.1 && 
          lngSpanDiff < 0.1) {
        return;
      }
    }
    
    _lastBounds = bounds;
    
    // Debounce the bounds change to avoid too many API calls while panning
    _boundsDebounce?.cancel();
    _boundsDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final salesService = context.read<SalesService>();
      salesService.loadSalesByBounds(
        minLat: bounds.minLat,
        maxLat: bounds.maxLat,
        minLng: bounds.minLng,
        maxLng: bounds.maxLng,
      );
    });
  }

  void _onSaleSelected(GarageSale sale) {
    setState(() {
      _selectedSale = sale;
    });
  }

  void _navigateToDetails(GarageSale sale) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleDetailsScreen(saleId: sale.id),
      ),
    );
  }

  void _navigateToCreate() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateSaleScreen(),
      ),
    );
  }

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_rounded),
          onPressed: () {},
          color: AppColors.primary,
        ),
        title: const Text(
          'Rummage',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search
            },
            color: AppColors.primary,
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: isDarkMode ? Colors.white : AppColors.lightTextPrimary,
            ),
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          const SavedScreen(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreate,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_outline),
            activeIcon: Icon(Icons.favorite),
            label: 'Saved',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),
        ),

        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildFilterChip('Today', Icons.calendar_today),
              const SizedBox(width: 8),
              _buildFilterChip('Filters', Icons.filter_list),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Map
        Expanded(
          child: Consumer2<SalesService, LocationService>(
            builder: (context, salesService, locationService, _) {
              // Only block the UI while we don't yet have a location to center the map.
              // IMPORTANT: Do NOT replace the map with a spinner during bounds fetches,
              // or the GoogleMap widget will be unmounted/remounted, resetting camera state.
              if (locationService.isLoading && !locationService.hasLocation) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!locationService.hasLocation) {
                return const Center(child: Text('Enable location to view nearby sales.'));
              }

              return Stack(
                children: [
                  SaleMap(
                    key: const ValueKey('sale_map'),
                    sales: salesService.sales,
                    userLatitude: locationService.latitude,
                    userLongitude: locationService.longitude,
                    onSaleSelected: _onSaleSelected,
                    selectedSale: _selectedSale,
                    onBoundsChanged: _onMapBoundsChanged,
                  ),

                  // Lightweight loading indicator while fetching sales (keep map mounted)
                  if (salesService.isLoading)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Loading…',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Selected sale card at bottom
                  if (_selectedSale != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: MapPinCard(
                        sale: _selectedSale!,
                        onTap: () => _navigateToDetails(_selectedSale!),
                        onClose: () => setState(() => _selectedSale = null),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, IconData icon) {
    final isSelected = _selectedFilter == label;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected
                ? Colors.white
                : (isDarkMode ? AppColors.darkTextPrimary : AppColors.primary),
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = selected ? label : 'All';
        });
      },
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected
            ? Colors.white
            : (isDarkMode ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
      ),
    );
  }
}

