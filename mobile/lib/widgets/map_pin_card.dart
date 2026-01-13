import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/garage_sale.dart';
import '../theme/app_colors.dart';

/// A compact card designed to overlay on the map when a sale marker is selected.
/// Shows seller name, dates/times, and active status prominently.
class MapPinCard extends StatelessWidget {
  final GarageSale sale;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const MapPinCard({
    super.key,
    required this.sale,
    this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.15 * 255).round()),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: sale.isActive
            ? Border.all(color: AppColors.success, width: 2)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with title and status
                Row(
                  children: [
                    // Status indicator
                    _buildStatusBadge(),
                    const SizedBox(width: 12),
                    // Title and close button
                    Expanded(
                      child: Text(
                        sale.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onClose != null)
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 20,
                          color: isDarkMode
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        onPressed: onClose,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Date and Time info
                _buildDateTimeRow(isDarkMode),
                const SizedBox(height: 8),

                // Address
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: isDarkMode
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        sale.address,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDarkMode
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Items count and view details
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (sale.items.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha((0.1 * 255).round()),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${sale.items.length} item${sale.items.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      const SizedBox(),
                    const Row(
                      children: [
                        Text(
                          'View Details',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (sale.isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.success,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'LIVE NOW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.mapPinInactive.withAlpha((0.2 * 255).round()),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _getStatusText(),
          style: const TextStyle(
            color: AppColors.mapPinInactive,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
  }

  String _getStatusText() {
    final now = DateTime.now();
    if (sale.startDate.isAfter(now)) {
      return 'UPCOMING';
    } else if (sale.endDate.isBefore(now)) {
      return 'ENDED';
    }
    return 'SCHEDULED';
  }

  Widget _buildDateTimeRow(bool isDarkMode) {
    final dateFormat = DateFormat('EEE, MMM d');
    final timeFormat = DateFormat('h:mm a');
    final now = DateTime.now();

    String dateText;
    if (sale.startDate.year == now.year &&
        sale.startDate.month == now.month &&
        sale.startDate.day == now.day) {
      dateText = 'Today';
    } else if (sale.startDate.year == now.year &&
        sale.startDate.month == now.month &&
        sale.startDate.day == now.day + 1) {
      dateText = 'Tomorrow';
    } else {
      dateText = dateFormat.format(sale.startDate);
    }

    final timeText =
        '${timeFormat.format(sale.startDate)} - ${timeFormat.format(sale.endDate)}';

    return Row(
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          size: 16,
          color: AppColors.primary,
        ),
        const SizedBox(width: 6),
        Text(
          dateText,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDarkMode
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
          ),
        ),
        const SizedBox(width: 12),
        const Icon(
          Icons.access_time,
          size: 16,
          color: AppColors.primary,
        ),
        const SizedBox(width: 6),
        Text(
          timeText,
          style: TextStyle(
            fontSize: 14,
            color: isDarkMode
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }
}


