import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

import '../models/garage_sale.dart';
import '../models/item.dart';
import '../services/sales_service.dart';
import '../services/auth_service.dart';
import '../services/favorite_service.dart';
import '../services/firebase_storage_service.dart';
import '../theme/app_colors.dart';
import 'add_item_screen.dart';
import 'item_details_screen.dart';

import '../widgets/sale_status_badge.dart';

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
  GarageSale? _selectedSale;
  String? _loadError;
  int _loadSeq = 0;

  final ImagePicker _imagePicker = ImagePicker();
  bool _isCoverUploading = false;
  double _coverUploadProgress = 0;
  bool _showCoverEditButton = false;
  bool _isDeletingSale = false;
  bool _isUpdatingSaleTime = false;
  @override
  void initState() {
    super.initState();
    _loadSaleDetails();
  }

  Future<void> _loadSaleDetails() async {
    // Increment a sequence number so stale responses (from older requests) can't win.
    final mySeq = ++_loadSeq;

    // Critical: clear the previously rendered sale immediately so we don't flash stale
    // title/images while the new sale loads.
    setState(() {
      _loadError = null;
      _selectedSale = null;
    });

    final sale = await context.read<SalesService>().getSaleDetails(widget.saleId);
    if (!mounted || mySeq != _loadSeq) return;

    setState(() {
      _selectedSale = sale;
      _loadError = sale == null ? context.read<SalesService>().error : null;
    });
  }

  @override
  void didUpdateWidget(covariant SaleDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.saleId != widget.saleId) {
      _loadSaleDetails();
    }
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

    // This screen keeps its own local `_selectedSale`; refresh so UI reflects the new status.
    if (mounted) {
      await _loadSaleDetails();
    }
  }

  Future<void> _toggleFavorite(String saleId) async {
    await context.read<FavoriteService>().toggleFavorite(saleId);
  }

  Future<void> _editSaleTime(GarageSale sale) async {
    if (_isUpdatingSaleTime) return;

    final dateFormat = DateFormat('EEEE, MMM d, yyyy');
    var selectedDate = DateTime(sale.startDate.year, sale.startDate.month, sale.startDate.day);
    var startTime = TimeOfDay.fromDateTime(sale.startDate);
    var endTime = TimeOfDay.fromDateTime(sale.endDate);

    final result = await showModalBottomSheet<_EditSaleTimeResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> pickDate() async {
                // Allow rescheduling to any date (including past dates).
                // `showDatePicker` asserts `initialDate` is within [firstDate, lastDate].
                final firstAllowedDate = DateTime(2000, 1, 1);
                final lastAllowedDate = DateTime(2100, 12, 31);
                final initialDate = selectedDate.isBefore(firstAllowedDate)
                    ? firstAllowedDate
                    : (selectedDate.isAfter(lastAllowedDate) ? lastAllowedDate : selectedDate);

                final picked = await showDatePicker(
                  context: context,
                  initialDate: initialDate,
                  firstDate: firstAllowedDate,
                  lastDate: lastAllowedDate,
                );
                if (picked == null) return;
                setSheetState(() {
                  selectedDate = picked;
                });
              }

              Future<void> pickStartTime() async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: startTime,
                );
                if (picked == null) return;
                setSheetState(() {
                  startTime = picked;
                });
              }

              Future<void> pickEndTime() async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: endTime,
                );
                if (picked == null) return;
                setSheetState(() {
                  endTime = picked;
                });
              }

              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Edit Date & Time',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Date'),
                              subtitle: Text(dateFormat.format(selectedDate)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: pickDate,
                            ),
                            const Divider(),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Start Time'),
                              subtitle: Text(startTime.format(context)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: pickStartTime,
                            ),
                            const Divider(),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('End Time'),
                              subtitle: Text(endTime.format(context)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: pickEndTime,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final start = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            startTime.hour,
                            startTime.minute,
                          );
                          final end = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            endTime.hour,
                            endTime.minute,
                          );
                          Navigator.of(context).pop(
                            _EditSaleTimeResult(start: start, end: end),
                          );
                        },
                        child: const Text('Save'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (result == null || !mounted) return;

    if (!result.end.isAfter(result.start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isUpdatingSaleTime = true;
    });

    final ok = await context.read<SalesService>().updateSale(
          sale.id,
          CreateSaleRequest(
            title: sale.title,
            description: sale.description,
            address: sale.address,
            latitude: sale.latitude,
            longitude: sale.longitude,
            startDate: result.start,
            endDate: result.end,
          ),
        );

    if (!mounted) return;
    setState(() {
      _isUpdatingSaleTime = false;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<SalesService>().error ?? 'Failed to update sale time.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    await _loadSaleDetails();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sale time updated'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteSale(String saleId) async {
    if (_isDeletingSale) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete sale?'),
        content: const Text(
          'This will permanently delete the sale and its items. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeletingSale = true;
    });

    final ok = await context.read<SalesService>().deleteSale(saleId);
    if (!mounted) return;

    setState(() {
      _isDeletingSale = false;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<SalesService>().error ?? 'Failed to delete sale.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Return the deleted sale id so callers (Home/Saved) can clear any stale selection.
    Navigator.of(context).pop<String>(saleId);
  }

  void _navigateToAddItem(String saleId) {
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (_) => AddItemScreen(saleId: saleId),
      ),
    )
        .then((created) async {
      // If an item was created, refresh the sale so the new item appears immediately.
      if (created == true && mounted) {
        await _loadSaleDetails();
      }
    });
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
          final sale = _selectedSale;

          if (sale == null) {
            if (_loadError != null && _loadError!.isNotEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadSaleDetails,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
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
                  _buildImageSection(sale, isDarkMode, isOwner),

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
                            SaleStatusBadge(
                              sale: sale,
                              compact: false,
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

  Widget _buildImageSection(GarageSale sale, bool isDarkMode, bool isOwner) {
    final hasCover = sale.saleCoverPhoto.isNotEmpty;

    return SizedBox(
      height: 200,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // UX: if a cover photo exists, tapping it reveals an edit button (pencil)
          // so the user learns the image is replaceable.
          if (hasCover && isOwner && !_isCoverUploading) {
            setState(() {
              _showCoverEditButton = !_showCoverEditButton;
            });
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover)
              CachedNetworkImage(
                imageUrl: sale.saleCoverPhoto,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: isDarkMode ? AppColors.darkSurface : AppColors.lightSurface,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  color: isDarkMode ? AppColors.darkSurface : AppColors.lightSurface,
                  child: const Icon(Icons.error),
                ),
              )
            else
              Container(
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
              ),

            if (_isCoverUploading)
              Container(
                color: Colors.black.withAlpha((0.35 * 255).round()),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        _coverUploadProgress > 0
                            ? 'Uploading… ${(_coverUploadProgress * 100).toInt()}%'
                            : 'Uploading…',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

            // If no cover photo, show a clear call-to-action for owners.
            if (!hasCover && isOwner)
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton.small(
                  heroTag: 'upload_sale_cover_${sale.id}',
                  onPressed: _isCoverUploading ? null : () => _showCoverImageOptions(sale.id),
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.add_a_photo, color: Colors.white),
                ),
              ),

            // If a cover exists, hide the edit affordance until the user taps the image.
            if (hasCover && isOwner && _showCoverEditButton)
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton.small(
                  heroTag: 'edit_sale_cover_${sale.id}',
                  onPressed: _isCoverUploading
                      ? null
                      : () {
                          setState(() {
                            _showCoverEditButton = false;
                          });
                          _showCoverImageOptions(sale.id);
                        },
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.edit, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showCoverImageOptions(String saleId) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                final image = await _imagePicker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1600,
                  maxHeight: 1600,
                  imageQuality: 85,
                );
                if (image != null && mounted) {
                  await _uploadCoverPhoto(saleId, image);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final image = await _imagePicker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1600,
                  maxHeight: 1600,
                  imageQuality: 85,
                );
                if (image != null && mounted) {
                  await _uploadCoverPhoto(saleId, image);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadCoverPhoto(String saleId, XFile image) async {
    setState(() {
      _isCoverUploading = true;
      _coverUploadProgress = 0;
    });

    final url = await FirebaseStorageService.uploadSaleCoverImage(
      imageFile: image,
      saleId: saleId,
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _coverUploadProgress = p;
        });
      },
    );

    if (!mounted) return;

    if (url == null || url.isEmpty) {
      setState(() {
        _isCoverUploading = false;
      });
      final reason = FirebaseStorageService.lastUploadError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason != null && reason.isNotEmpty
                ? 'Failed to upload cover photo: $reason'
                : 'Failed to upload cover photo. Please try again.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final updated = await context.read<SalesService>().setSaleCoverPhoto(saleId, url);

    if (!mounted) return;

    setState(() {
      _isCoverUploading = false;
      _coverUploadProgress = 0;
      if (updated != null) {
        _selectedSale = updated;
      }
    });

    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<SalesService>().error ?? 'Failed to save cover photo.'),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cover photo updated!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Widget _buildOwnerControls(GarageSale sale) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Sale Controls',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'edit_time') {
                      _editSaleTime(sale);
                    } else if (value == 'delete') {
                      _deleteSale(sale.id);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit_time',
                      child: Text('Edit time'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete sale'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        (_isDeletingSale || _isUpdatingSaleTime) ? null : () => _toggleSaleStatus(sale),
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
        final item = items[index];
        return InkWell(
          onTap: () async {
            final deleted = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => ItemDetailsScreen(
                  saleId: widget.saleId,
                  item: item,
                  isOwner: isOwner,
                ),
              ),
            );

            // This screen maintains a local copy of sale details; refresh to reflect edits/deletes.
            if (mounted) {
              await _loadSaleDetails();
            }

            // If deleted, no extra action needed; refresh already handled.
            if (deleted == true && mounted) {
              // no-op
            }
          },
          child: _ItemCard(item: item),
        );
      },
    );
  }

  String _formatDateRange(GarageSale sale) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    
    return '${dateFormat.format(sale.startDate)} ${timeFormat.format(sale.startDate)} - ${timeFormat.format(sale.endDate)}';
  }
}

class _ItemCard extends StatelessWidget {
  final Item item;

  const _ItemCard({
    required this.item,
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
                item.primaryImageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.primaryImageUrl,
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
                // Delete/edit actions live on the Item Details screen now.
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
                        color: AppColors.primary.withAlpha((0.1 * 255).round()),
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

class _EditSaleTimeResult {
  final DateTime start;
  final DateTime end;  const _EditSaleTimeResult({
    required this.start,
    required this.end,
  });
}
