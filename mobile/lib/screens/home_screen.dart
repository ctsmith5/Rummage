import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/garage_sale.dart';
import '../services/auth_service.dart';
import '../services/sales_service.dart';
import '../services/location_service.dart';
import '../services/favorite_service.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';
import '../widgets/map_pin_card.dart';
import '../widgets/sale_map.dart';
import 'saved_screen.dart';
import 'my_sales_screen.dart';
import 'sale_details_screen.dart';
import 'auth/login_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  GarageSale? _selectedSale;
  Timer? _boundsDebounce;
  int _fitSeq = 0;
  FitBoundsRequest? _fitBoundsRequest;
  double _searchRadius = 10.0;
  bool _showRadiusSlider = false;
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    // Defer data loading until after build to avoid notifyListeners during build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadData();
    });
    _searchFocusNode.addListener(() {
      if (!mounted) return;
      // Reveal radius slider when user is interacting with search.
      setState(() {
        _showRadiusSlider = _searchFocusNode.hasFocus;
      });
    });
  }

  Future<void> _loadData() async {
    final locationService = context.read<LocationService>();
    final salesService = context.read<SalesService>();
    // Prefetch profile so ProfileScreen can render with data immediately.
    // Don't block map load on this.
    // ignore: unawaited_futures
    context.read<ProfileService>().loadProfile();
    await locationService.getCurrentLocation();
    if (!mounted) return;

    if (locationService.hasLocation) {
      await salesService.loadNearbySales(
        locationService.latitude,
        locationService.longitude,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _boundsDebounce?.cancel();
    super.dispose();
  }

  MapBounds? _lastBounds;
  bool _isInitialBoundsLoad = true;
  
  void _onMapBoundsChanged(MapBounds bounds) {
    final previousBounds = _lastBounds;

    // Always track the latest visible bounds so search can use the map center.
    _lastBounds = bounds;

    // Mark initial bounds load as complete, but do not skip loading anymore.
    if (_isInitialBoundsLoad) {
      _isInitialBoundsLoad = false;
    }

    // If search is active, don't keep replacing the search results with bounds loads.
    if (_isSearchMode) return;

    // Skip if bounds haven't changed significantly (avoid unnecessary API calls)
    if (previousBounds != null) {
      // Calculate center of bounds
      final oldCenterLat = (previousBounds.minLat + previousBounds.maxLat) / 2;
      final oldCenterLng = (previousBounds.minLng + previousBounds.maxLng) / 2;
      final newCenterLat = (bounds.minLat + bounds.maxLat) / 2;
      final newCenterLng = (bounds.minLng + bounds.maxLng) / 2;

      // Calculate span (size) of bounds
      final oldLatSpan = (previousBounds.maxLat - previousBounds.minLat).abs();
      final oldLngSpan = (previousBounds.maxLng - previousBounds.minLng).abs();
      final newLatSpan = (bounds.maxLat - bounds.minLat).abs();
      final newLngSpan = (bounds.maxLng - bounds.minLng).abs();

      // Guard against divide-by-zero (shouldn't happen, but keep this safe).
      final latSpanDiff = oldLatSpan == 0 ? 1.0 : (newLatSpan - oldLatSpan).abs() / oldLatSpan;
      final lngSpanDiff = oldLngSpan == 0 ? 1.0 : (newLngSpan - oldLngSpan).abs() / oldLngSpan;

      // Check if center moved significantly (more than 5% of span) or zoom changed (more than 10% span change)
      final centerLatDiff = (newCenterLat - oldCenterLat).abs();
      final centerLngDiff = (newCenterLng - oldCenterLng).abs();

      // Only update if bounds changed significantly
      if (centerLatDiff < oldLatSpan * 0.05 &&
          centerLngDiff < oldLngSpan * 0.05 &&
          latSpanDiff < 0.1 &&
          lngSpanDiff < 0.1) {
        return;
      }
    }
    
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

  Future<void> _navigateToDetails(GarageSale sale) async {
    final deletedSaleId = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => SaleDetailsScreen(saleId: sale.id),
      ),
    );

    if (!mounted) return;
    if (deletedSaleId == sale.id) {
      setState(() {
        _selectedSale = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sale deleted')),
      );
      return;
    }

    // When returning from Sale Details, the sale may have been started/ended.
    // The map pins are driven by SalesService (so they update), but the bottom
    // card uses our local `_selectedSale` reference, which can be stale.
    final salesService = context.read<SalesService>();
    final refreshed = salesService.sales.firstWhere(
      (s) => s.id == sale.id,
      orElse: () => _selectedSale ?? sale,
    );
    setState(() {
      _selectedSale = refreshed;
    });
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
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        // No create button in AppBar (moved to My Sales tab).
        title: const Text(
          'Rummage',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.person_outline,
              color: AppColors.primary,
            ),
            onPressed: () {
              final initial = context.read<ProfileService>().profile;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProfileScreen(initialProfile: initial)),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          const SavedScreen(),
          const MySalesScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });

          // Saved tab is kept alive by IndexedStack; force a refresh when selected.
          if (index == 1) {
            final favs = context.read<FavoriteService>();
            favs.loadFavorites();
            favs.loadFavoritedSales();
          }
          // My Sales tab is also kept alive; force refresh when selected.
          if (index == 2) {
            context.read<SalesService>().loadMySales();
          }
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
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront_outlined),
            activeIcon: Icon(Icons.storefront),
            label: 'My Sales',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    final showRadiusSlider = _showRadiusSlider;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchFocusNode.unfocus();
                        setState(() {
                          _fitBoundsRequest = null;
                          _showRadiusSlider = false;
                          _isSearchMode = false;
                        });
                        // Return to normal bounds loading when clearing search.
                        final b = _lastBounds;
                        if (b != null) {
                          context.read<SalesService>().loadSalesByBounds(
                                minLat: b.minLat,
                                maxLat: b.maxLat,
                                minLng: b.minLng,
                                maxLng: b.maxLng,
                              );
                        } else {
                          final loc = context.read<LocationService>();
                          if (loc.hasLocation) {
                            context
                                .read<SalesService>()
                                .loadNearbySales(loc.latitude, loc.longitude);
                          }
                        }
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              final trimmed = value.trim();
              if (trimmed.isEmpty && _showRadiusSlider) {
                setState(() {
                  _showRadiusSlider = false;
                });
              } else {
                setState(() {});
              }
            },
            textInputAction: TextInputAction.search,
            onSubmitted: (value) async {
              final q = value.trim();
              if (q.isEmpty) return;
              FocusScope.of(context).unfocus();

              final loc = context.read<LocationService>();
              if (!loc.hasLocation) return;

              // Use the map center (current visible bounds) if available.
              final b = _lastBounds;
              final centerLat = b != null ? (b.minLat + b.maxLat) / 2 : loc.latitude;
              final centerLng = b != null ? (b.minLng + b.maxLng) / 2 : loc.longitude;

              setState(() {
                _isSearchMode = true;
              });

              final results = await context.read<SalesService>().searchNearbySales(
                    lat: centerLat,
                    lng: centerLng,
                    radius: _searchRadius,
                    query: q,
                  );

              if (!mounted) return;
              if (results.isEmpty) return;

              double minLat = results.first.latitude;
              double maxLat = results.first.latitude;
              double minLng = results.first.longitude;
              double maxLng = results.first.longitude;
              for (final s in results) {
                if (s.latitude < minLat) minLat = s.latitude;
                if (s.latitude > maxLat) maxLat = s.latitude;
                if (s.longitude < minLng) minLng = s.longitude;
                if (s.longitude > maxLng) maxLng = s.longitude;
              }

              // Slightly pad bounds so pins aren't tight to edges.
              final padLat = (maxLat - minLat).abs() * 0.10;
              final padLng = (maxLng - minLng).abs() * 0.10;
              final sw = LatLng(minLat - padLat, minLng - padLng);
              final ne = LatLng(maxLat + padLat, maxLng + padLng);

              setState(() {
                _fitSeq++;
                _fitBoundsRequest = FitBoundsRequest(
                  bounds: LatLngBounds(southwest: sw, northeast: ne),
                  seq: _fitSeq,
                );
              });
            },
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
                    fitBoundsRequest: _fitBoundsRequest,
                    onMapTap: (_) {
                      if (_searchFocusNode.hasFocus || _showRadiusSlider) {
                        _searchFocusNode.unfocus();
                        setState(() {
                          _showRadiusSlider = false;
                        });
                      }

                      // Exiting "search mode" should restore normal bounds-based loading.
                      if (_isSearchMode) {
                        setState(() {
                          _isSearchMode = false;
                          _fitBoundsRequest = null;
                        });
                        final b = _lastBounds;
                        if (b != null) {
                          context.read<SalesService>().loadSalesByBounds(
                                minLat: b.minLat,
                                maxLat: b.maxLat,
                                minLng: b.minLng,
                                maxLng: b.maxLng,
                              );
                        } else {
                          final loc = context.read<LocationService>();
                          if (loc.hasLocation) {
                            context
                                .read<SalesService>()
                                .loadNearbySales(loc.latitude, loc.longitude);
                          }
                        }
                      }
                    },
                  ),

                  // Radius slider overlay (does not resize the map).
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: !showRadiusSlider
                          ? const SizedBox.shrink()
                          : Material(
                              key: const ValueKey('radius_slider_overlay'),
                              elevation: 2,
                              borderRadius: BorderRadius.circular(12),
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: Row(
                                  children: [
                                    const Text('10'),
                                    Expanded(
                                      child: Slider(
                                        min: 10,
                                    max: 500,
                                    divisions: 49, // 10-mile increments
                                    value: _searchRadius.clamp(10, 500),
                                        label: '${_searchRadius.round()} mi',
                                        onChanged: (v) {
                                          setState(() {
                                            _searchRadius = v;
                                          });
                                        },
                                      ),
                                    ),
                                const Text('500'),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),

                  // Lightweight loading indicator while fetching sales (keep map mounted)
                  if (salesService.isLoading)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha((0.6 * 255).round()),
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
                  if (_selectedSale != null &&
                      salesService.sales.any((s) => s.id == _selectedSale!.id))
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: MapPinCard(
                        sale: _selectedSale!,
                        onTap: () async => _navigateToDetails(_selectedSale!),
                        onClose: () => setState(() => _selectedSale = null),
                      ),
                    ),
                  if (_selectedSale != null &&
                      !salesService.sales.any((s) => s.id == _selectedSale!.id))
                    // If the selected sale no longer exists in the current pins (e.g. deleted),
                    // clear it after the frame so we don't keep showing a broken card.
                    Builder(
                      builder: (_) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() => _selectedSale = null);
                        });
                        return const SizedBox.shrink();
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

