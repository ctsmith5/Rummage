import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/garage_sale.dart';
import '../theme/app_colors.dart';
import '../theme/map_styles.dart';

/// Check if Google Maps is supported on this platform
bool get isGoogleMapsSupported {
  if (kIsWeb) return true;
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (e) {
    return false;
  }
}

/// Represents the visible bounds of the map
class MapBounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const MapBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });
}

/// Main map widget - uses Google Maps on Android/iOS/Web, placeholder on desktop
class SaleMap extends StatefulWidget {
  final List<GarageSale> sales;
  final double userLatitude;
  final double userLongitude;
  final Function(GarageSale)? onSaleSelected;
  final GarageSale? selectedSale;
  final Function(MapBounds)? onBoundsChanged;

  const SaleMap({
    super.key,
    required this.sales,
    required this.userLatitude,
    required this.userLongitude,
    this.onSaleSelected,
    this.selectedSale,
    this.onBoundsChanged,
  });

  @override
  State<SaleMap> createState() => _SaleMapState();
}

class _SaleMapState extends State<SaleMap> {
  GoogleMapController? _mapController;
  bool _isInitialLoad = true;
  CameraPosition? _initialCameraPosition;
  bool _isUserInteracting = false;

  @override
  void initState() {
    super.initState();
    // Store initial camera position only once
    if (widget.userLatitude != 0 && widget.userLongitude != 0) {
      _initialCameraPosition = CameraPosition(
        target: LatLng(widget.userLatitude, widget.userLongitude),
        zoom: 14.0,
      );
    }
  }

  @override
  void didUpdateWidget(SaleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update initial position if it was zero before and now has a value
    // This prevents recentering when location updates occur
    if (_initialCameraPosition == null && 
        widget.userLatitude != 0 && 
        widget.userLongitude != 0) {
      _initialCameraPosition = CameraPosition(
        target: LatLng(widget.userLatitude, widget.userLongitude),
        zoom: 14.0,
      );
    }
    // Don't reset initial load flag when widget updates (e.g., when sales change)
    // This prevents triggering bounds changes when only sales data updates
  }

  Future<void> _onCameraIdle() async {
    if (_mapController == null) return;
    
    // Only trigger bounds change if user was interacting (panning/zooming)
    // This prevents triggering on initial load or when sales update
    if (!_isUserInteracting && !_isInitialLoad) {
      return;
    }
    
    // Reset interaction flag when camera stops moving
    _isUserInteracting = false;
    
    final bounds = await _mapController!.getVisibleRegion();
    final mapBounds = MapBounds(
      minLat: bounds.southwest.latitude,
      maxLat: bounds.northeast.latitude,
      minLng: bounds.southwest.longitude,
      maxLng: bounds.northeast.longitude,
    );
    widget.onBoundsChanged?.call(mapBounds);
  }

  void _onCameraMoveStarted() {
    // Mark that user is interacting with the map
    _isUserInteracting = true;
  }
  
  Set<Marker> _buildMarkers() {
    return widget.sales.map((sale) {
      final isSelected = sale.id == widget.selectedSale?.id;
      return Marker(
        markerId: MarkerId(sale.id),
        position: LatLng(sale.latitude, sale.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          sale.isActive 
              ? BitmapDescriptor.hueOrange
              : BitmapDescriptor.hueRed,
        ),
        infoWindow: InfoWindow(
          title: sale.title,
          snippet: sale.isActive ? '🟢 LIVE NOW' : sale.address,
          onTap: () => widget.onSaleSelected?.call(sale),
        ),
        onTap: () => widget.onSaleSelected?.call(sale),
        zIndex: isSelected ? 1.0 : 0.0,
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    // Use placeholder on desktop platforms
    if (!isGoogleMapsSupported) {
      return SaleMapPlaceholder(
        sales: widget.sales,
        onSaleSelected: widget.onSaleSelected,
        selectedSaleId: widget.selectedSale?.id,
        userLatitude: widget.userLatitude,
        userLongitude: widget.userLongitude,
      );
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Use default position if initial position not set yet
    final cameraPosition = _initialCameraPosition ?? CameraPosition(
      target: const LatLng(0, 0),
      zoom: 14.0,
    );
    
    return GoogleMap(
      initialCameraPosition: cameraPosition,
      markers: _buildMarkers(),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      mapToolbarEnabled: false,
      zoomControlsEnabled: true,
      compassEnabled: true,
      onMapCreated: (controller) async {
        // Only set controller if it hasn't been set yet (prevents reset on rebuild)
        if (_mapController == null) {
          _mapController = controller;
          if (isDarkMode) {
            controller.setMapStyle(MapStyles.darkMapStyle);
          }
          // Mark initial load as complete - don't trigger bounds change on initial load
          // The home screen will load nearby sales based on user location instead
          _isInitialLoad = false;
        }
      },
      onCameraMoveStarted: _onCameraMoveStarted,
      onCameraIdle: _onCameraIdle,
      style: isDarkMode ? MapStyles.darkMapStyle : null,
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

/// Placeholder widget for map display (works on all platforms)
class SaleMapPlaceholder extends StatelessWidget {
  final List<GarageSale> sales;
  final Function(GarageSale)? onSaleSelected;
  final String? selectedSaleId;
  final double userLatitude;
  final double userLongitude;

  const SaleMapPlaceholder({
    super.key,
    required this.sales,
    this.onSaleSelected,
    this.selectedSaleId,
    this.userLatitude = 0,
    this.userLongitude = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Container(
      color: isDarkMode ? AppColors.darkSurface : const Color(0xFFE8E8E8),
      child: Stack(
        children: [
          // Grid pattern to simulate map
          CustomPaint(
            size: Size.infinite,
            painter: _GridPainter(isDarkMode: isDarkMode),
          ),

          // "Map not available" banner for desktop
          if (!isGoogleMapsSupported)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.black54 : Colors.white70,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Map preview - Run on mobile/web for full maps',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // No sales message
          if (sales.isEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.black54 : Colors.white70,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_off,
                      size: 48,
                      color: isDarkMode ? Colors.white54 : Colors.black45,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No garage sales nearby',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create one with the + button!',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Sale pins - distributed across the visible area
          ...sales.asMap().entries.map((entry) {
            final index = entry.key;
            final sale = entry.value;
            final isSelected = sale.id == selectedSaleId;
            
            // Distribute pins in a grid pattern across the map
            final columns = 3;
            final row = index ~/ columns;
            final col = index % columns;
            
            final xSpacing = (size.width - 100) / columns;
            final ySpacing = 100.0;
            
            return Positioned(
              left: 50.0 + col * xSpacing,
              top: 100.0 + row * ySpacing,
              child: GestureDetector(
                onTap: () => onSaleSelected?.call(sale),
                child: Column(
                  children: [
                    Container(
                      decoration: isSelected
                          ? BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            )
                          : null,
                      child: Icon(
                        Icons.location_pin,
                        color: sale.isActive
                            ? AppColors.primary
                            : AppColors.mapPinInactive,
                        size: isSelected ? 48 : 40,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.black54 : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sale.title.length > 15 
                            ? '${sale.title.substring(0, 15)}...' 
                            : sale.title,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDarkMode ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (sale.isActive)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          
          // Decorative street labels
          Positioned(
            right: 20,
            top: 150,
            child: Text(
              'Sequoia Park',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          
          Positioned(
            left: 20,
            bottom: 80,
            child: Text(
              'Sunset Ave',
              style: TextStyle(
                color: isDarkMode ? Colors.grey : Colors.grey.shade600,
                fontSize: 11,
              ),
            ),
          ),

          Positioned(
            left: size.width * 0.4,
            top: size.height * 0.3,
            child: Text(
              'Main St',
              style: TextStyle(
                color: isDarkMode ? Colors.grey : Colors.grey.shade600,
                fontSize: 11,
              ),
            ),
          ),

          // Legend
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.black54 : Colors.white70,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_pin, color: AppColors.primary, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Active Sale',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_pin, color: AppColors.mapPinInactive, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Inactive',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final bool isDarkMode;

  _GridPainter({required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDarkMode
          ? Colors.grey.shade800
          : Colors.grey.shade300
      ..strokeWidth = 1;

    // Draw horizontal lines (roads)
    for (double y = 0; y < size.height; y += 60) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw vertical lines (roads)
    for (double x = 0; x < size.width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw some "parks" (green rectangles)
    final parkPaint = Paint()
      ..color = isDarkMode
          ? Colors.green.shade900.withOpacity(0.3)
          : Colors.green.shade200.withOpacity(0.5);
    
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.7, size.height * 0.2, size.width * 0.25, size.height * 0.3),
      parkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
