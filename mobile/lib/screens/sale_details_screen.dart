import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/garage_sale.dart';
import '../models/item.dart';
import '../services/sales_service.dart';
import '../services/auth_service.dart';
import '../services/favorite_service.dart';
import '../theme/app_colors.dart';
import 'add_item_screen.dart';

class SaleDetailsScreen extends StatefulWidget {
  final String saleId;

  const SaleDetailsScreen({
    super.key,
    required this.saleId,
  });

  @override
  State<SaleDetailsScreen> createState() => _SaleDetailsScreenState();
}

class _SaleDetailsScreenState extends State<SaleDetailsScreen> {
  @override
  void initState() {
    super.initState();
    _loadSaleDetails();
  }

  Future<void> _loadSaleDetails() async {
    await context.read<SalesService>().getSaleDetails(widget.saleId);
  }

  Future<void> _openMaps(GarageSale sale) async {
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${sale.latitude},${sale.longitude}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _toggleSaleStatus(GarageSale sale) async {
    final salesService = context.read<SalesService>();
    if (sale.isActive) {
      await salesService.endSale(sale.id);
    } else {
      await salesService.startSale(sale.id);
    }
  }

  Future<void> _toggleFavorite(String saleId) async {
    await context.read<FavoriteService>().toggleFavorite(saleId);
  }

  void _navigateToAddItem(String saleId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddItemScreen(saleId: saleId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale Details'),
        actions: [
          Consumer<FavoriteService>(
            builder: (context, favoriteService, _) {
              final isFavorited = favoriteService.isFavorited(widget.saleId);
              return IconButton(
                icon: Icon(
                  isFavorited ? Icons.favorite : Icons.favorite_border,
                  color: isFavorited ? AppColors.error : null,
                ),
                onPressed: () => _toggleFavorite(widget.saleId),
              );
            },
          ),
        ],
      ),
      body: Consumer2<SalesService, AuthService>(
        builder: (context, salesService, authService, _) {
          final sale = salesService.selectedSale;

          if (sale == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final isOwner = sale.userId == authService.currentUser?.id;

          return RefreshIndicator(
            onRefresh: _loadSaleDetails,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header image/carousel
                  _buildImageSection(sale, isDarkMode),

                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title and status
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                sale.title,
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                            ),
                            if (sale.isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'LIVE NOW',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Date and time
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDateRange(sale),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Address
                        GestureDetector(
                          onTap: () => _openMaps(sale),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  sale.address,
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextSecondary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),

                        if (sale.description.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            sale.description,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],

                        // Owner controls
                        if (isOwner) ...[
                          const SizedBox(height: 24),
                          _buildOwnerControls(sale),
                        ],

                        const SizedBox(height: 24),

                        // Items section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Items (${sale.items.length})',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (isOwner)
                              TextButton.icon(
                                onPressed: () => _navigateToAddItem(sale.id),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Item'),
                              ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        if (sale.items.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 48,
                                    color: isDarkMode
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextSecondary,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No items listed yet',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          _buildItemsGrid(sale.items, isOwner),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageSection(GarageSale sale, bool isDarkMode) {
    if (sale.items.isEmpty || sale.items.every((i) => i.imageUrl.isEmpty)) {
      return Container(
        height: 200,
        color: isDarkMode ? AppColors.darkSurface : AppColors.lightSurface,
        child: Center(
          child: Icon(
            Icons.storefront,
            size: 64,
            color: isDarkMode
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
        ),
      );
    }

    final imagesWithUrl = sale.items.where((i) => i.imageUrl.isNotEmpty).toList();

    return SizedBox(
      height: 200,
      child: PageView.builder(
        itemCount: imagesWithUrl.length,
        itemBuilder: (context, index) {
          return CachedNetworkImage(
            imageUrl: imagesWithUrl[index].imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: isDarkMode ? AppColors.darkSurface : AppColors.lightSurface,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => Container(
              color: isDarkMode ? AppColors.darkSurface : AppColors.lightSurface,
              child: const Icon(Icons.error),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOwnerControls(GarageSale sale) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sale Controls',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _toggleSaleStatus(sale),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          sale.isActive ? AppColors.error : AppColors.success,
                    ),
                    icon: Icon(sale.isActive ? Icons.stop : Icons.play_arrow),
                    label: Text(sale.isActive ? 'End Sale' : 'Start Sale'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsGrid(List<Item> items, bool isOwner) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _ItemCard(
          item: items[index],
          isOwner: isOwner,
          onDelete: isOwner
              ? () => _deleteItem(items[index])
              : null,
        );
      },
    );
  }

  Future<void> _deleteItem(Item item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await context.read<SalesService>().deleteItem(widget.saleId, item.id);
    }
  }

  String _formatDateRange(GarageSale sale) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    
    return '${dateFormat.format(sale.startDate)} ${timeFormat.format(sale.startDate)} - ${timeFormat.format(sale.endDate)}';
  }
}

class _ItemCard extends StatelessWidget {
  final Item item;
  final bool isOwner;
  final VoidCallback? onDelete;

  const _ItemCard({
    required this.item,
    required this.isOwner,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                item.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: isDarkMode
                              ? AppColors.darkSurface
                              : AppColors.lightSurface,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) =>
                            _buildPlaceholder(isDarkMode),
                      )
                    : _buildPlaceholder(isDarkMode),
                if (isOwner)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.delete,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      onPressed: onDelete,
                    ),
                  ),
              ],
            ),
          ),

          // Details
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.formattedPrice,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (item.category.isNotEmpty) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.category,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(bool isDarkMode) {
    return Container(
      color: isDarkMode ? AppColors.darkSurface : AppColors.lightSurface,
      child: Icon(
        Icons.image_outlined,
        size: 40,
        color: isDarkMode
            ? AppColors.darkTextSecondary
            : AppColors.lightTextSecondary,
      ),
    );
  }
}

