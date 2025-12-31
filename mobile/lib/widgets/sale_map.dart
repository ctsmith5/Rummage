import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/garage_sale.dart';
import '../theme/app_colors.dart';
import '../theme/map_styles.dart';

class SaleMap extends StatefulWidget {
  final List<GarageSale> sales;
  final double userLatitude;
  final double userLongitude;
  final Function(GarageSale)? onSaleSelected;
  final GarageSale? selectedSale;

  const SaleMap({
    super.key,
    required this.sales,
    required this.userLatitude,
    required this.userLongitude,
    this.onSaleSelected,
    this.selectedSale,
  });

  @override
  State<SaleMap> createState() => _SaleMapState();
}

class _SaleMapState extends State<SaleMap> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  @override
  void didUpdateWidget(SaleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sales != widget.sales ||
        oldWidget.selectedSale != widget.selectedSale) {
      _buildMarkers();
    }
  }

  void _buildMarkers() {
    final markers = <Marker>{};

    for (final sale in widget.sales) {
      final isSelected = widget.selectedSale?.id == sale.id;

      markers.add(
        Marker(
          markerId: MarkerId(sale.id),
          position: LatLng(sale.latitude, sale.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            sale.isActive
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueRed,
          ),
          onTap: () {
            widget.onSaleSelected?.call(sale);
          },
          infoWindow: InfoWindow(
            title: sale.title,
            snippet: sale.address,
          ),
        ),
      );
    }

    setState(() {
      _markers = markers;
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    // Apply dark mode style if needed
    final isDarkMode =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    if (isDarkMode) {
      _mapController?.setMapStyle(MapStyles.darkMapStyle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialPosition = LatLng(
      widget.userLatitude != 0 ? widget.userLatitude : 37.7749,
      widget.userLongitude != 0 ? widget.userLongitude : -122.4194,
    );

    return GoogleMap(
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: initialPosition,
        zoom: 13,
      ),
      markers: _markers,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

// Placeholder widget when Google Maps is not available
class SaleMapPlaceholder extends StatelessWidget {
  final List<GarageSale> sales;
  final Function(GarageSale)? onSaleSelected;

  const SaleMapPlaceholder({
    super.key,
    required this.sales,
    this.onSaleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDarkMode ? AppColors.darkSurface : const Color(0xFFE8E8E8),
      child: Stack(
        children: [
          // Grid pattern to simulate map
          CustomPaint(
            size: Size.infinite,
            painter: _GridPainter(isDarkMode: isDarkMode),
          ),
          
          // Sale pins
          ...sales.asMap().entries.map((entry) {
            final index = entry.key;
            final sale = entry.value;
            
            // Distribute pins across the map area
            final row = index ~/ 3;
            final col = index % 3;
            
            return Positioned(
              left: 50.0 + col * 120,
              top: 80.0 + row * 100,
              child: GestureDetector(
                onTap: () => onSaleSelected?.call(sale),
                child: Icon(
                  Icons.location_pin,
                  color: sale.isActive
                      ? AppColors.primary
                      : AppColors.mapPinInactive,
                  size: 40,
                ),
              ),
            );
          }),
          
          // Park label (decorative)
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
          
          // Street label (decorative)
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

    // Draw horizontal lines
    for (double y = 0; y < size.height; y += 50) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw vertical lines
    for (double x = 0; x < size.width; x += 50) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

