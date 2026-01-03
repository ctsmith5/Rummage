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

  void _onMapBoundsChanged(MapBounds bounds) {
    // Debounce the bounds change to avoid too many API calls while panning
    _boundsDebounce?.cancel();
    _boundsDebounce = Timer(const Duration(milliseconds: 500), () {
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
              if (salesService.isLoading || locationService.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              return Stack(
                children: [
                  SaleMap(
                    sales: salesService.sales,
                    userLatitude: locationService.latitude,
                    userLongitude: locationService.longitude,
                    onSaleSelected: _onSaleSelected,
                    selectedSale: _selectedSale,
                    onBoundsChanged: _onMapBoundsChanged,
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

