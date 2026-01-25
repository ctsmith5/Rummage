import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/garage_sale.dart';
import '../theme/app_colors.dart';
import 'sale_status_badge.dart';

class SaleCard extends StatelessWidget {
  final GarageSale sale;
  final VoidCallback? onTap;
  final bool showDetailsButton;
  final bool showDistance;
  final double? distanceMiles;

  const SaleCard({
    super.key,
    required this.sale,
    this.onTap,
    this.showDetailsButton = false,
    this.showDistance = false,
    this.distanceMiles,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Sale image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 80,
                  height: 80,
                  color: isDarkMode
                      ? AppColors.darkSurface
                      : AppColors.lightSurface,
                  child: sale.saleCoverPhoto.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: sale.saleCoverPhoto,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          errorWidget: (context, url, error) =>
                              _buildPlaceholderImage(isDarkMode),
                        )
                      : _buildPlaceholderImage(isDarkMode),
                ),
              ),
              const SizedBox(width: 12),

              // Sale details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sale.title,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SaleStatusBadge(sale: sale),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateRange(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sale.address,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showDistance && distanceMiles != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${distanceMiles!.toStringAsFixed(1)} mi away',
                          style: TextStyle(
                            color: isDarkMode
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Details button
              if (showDetailsButton) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onTap,
                  child: const Text('See Details'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(bool isDarkMode) {
    return Container(
      color: isDarkMode ? AppColors.darkSurface : AppColors.lightSurface,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: isDarkMode
              ? AppColors.darkTextSecondary
              : AppColors.lightTextSecondary,
          size: 32,
        ),
      ),
    );
  }

  String _formatDateRange() {
    final now = DateTime.now();
    final startDate = sale.startDate;
    final endDate = sale.endDate;
    final timeFormat = DateFormat('h a');

    if (startDate.year == now.year &&
        startDate.month == now.month &&
        startDate.day == now.day) {
      return 'Today - ${timeFormat.format(startDate)}-${timeFormat.format(endDate)}';
    } else if (startDate.year == now.year &&
        startDate.month == now.month &&
        startDate.day == now.day + 1) {
      return 'Tomorrow - ${timeFormat.format(startDate)}-${timeFormat.format(endDate)}';
    } else {
      final dateFormat = DateFormat('MMM d');
      return '${dateFormat.format(startDate)} - ${timeFormat.format(startDate)}-${timeFormat.format(endDate)}';
    }
  }
}
