import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

import '../models/garage_sale.dart';
import '../models/item.dart';
import '../models/public_profile.dart';
import '../services/sales_service.dart';
import '../services/auth_service.dart';
import '../services/favorite_service.dart';
import '../services/firebase_storage_service.dart';
import '../services/profile_service.dart';
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

  PublicProfile? _ownerProfile;
  String? _ownerUserId;
  bool _ownerLoading = false;

  final ImagePicker _imagePicker = ImagePicker();
  bool _isCoverUploading = false;
  double _coverUploadProgress = 0;
  bool _showCoverEditButton = false;
  bool _isDeletingSale = false;
  bool _isUpdatingSaleTime = false;
  File? _localCoverFile;
  String _coverStatusText = 'Uploading...';
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
      _localCoverFile = null;
    });

    final sale = await context.read<SalesService>().getSaleDetails(widget.saleId);
    if (!mounted || mySeq != _loadSeq) return;

    setState(() {
      _selectedSale = sale;
      _loadError = sale == null ? context.read<SalesService>().error : null;
    });

    if (sale != null) {
      _loadOwnerProfileIfNeeded(sale.userId);
    }
  }

  Future<void> _loadOwnerProfileIfNeeded(String userId) async {
    if (_ownerUserId == userId && (_ownerProfile != null || _ownerLoading)) return;
    setState(() {
      _ownerUserId = userId;
      _ownerProfile = null;
      _ownerLoading = true;
    });
    final prof = await context.read<ProfileService>().loadPublicProfile(userId);
    if (!mounted) return;
    setState(() {
      _ownerProfile = prof;
      _ownerLoading = false;
    });
  }

  Future<void> _emailOwner() async {
    final email = (_ownerProfile?.email ?? '').trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Owner email not available')),
      );
      return;
    }
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open email app')),
      );
    }
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

  // Status is driven entirely by the scheduled window (start/end times).
  // We do not expose manual Start/End controls anymore.

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
    final controller = TextEditingController();
    var canDelete = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete sale'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will permanently delete the sale and its items. This action cannot be undone.',
              ),
              const SizedBox(height: 12),
              const Text('Type DELETE to confirm:'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (v) {
                  final ok = v.trim() == 'DELETE';
                  if (ok != canDelete) {
                    setDialogState(() {
                      canDelete = ok;
                    });
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'DELETE',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: canDelete ? () => Navigator.of(context).pop(true) : null,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
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

                        // Info bar: schedule+address (left) + owner identity/email (right)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap: isOwner ? () => _editSaleTime(sale) : null,
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.calendar_today,
                                              size: 18,
                                              color: AppColors.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _formatDateRange(sale),
                                                style: TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w600,
                                                  decoration: null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
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
                                                  decoration: null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                InkWell(
                                  onTap: _emailOwner,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_ownerLoading)
                                          const SizedBox(
                                            width: 44,
                                            height: 44,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        else
                                          CircleAvatar(
                                            radius: 22,
                                            backgroundColor: AppColors.lightSurface,
                                            backgroundImage: (_ownerProfile?.photoUrl ?? '').isNotEmpty
                                                ? NetworkImage(_ownerProfile!.photoUrl)
                                                : null,
                                            child: (_ownerProfile?.photoUrl ?? '').isEmpty
                                                ? const Icon(Icons.person, color: AppColors.primary)
                                                : null,
                                          ),
                                        const SizedBox(height: 6),
                                        SizedBox(
                                          width: 96,
                                          child: Text(
                                            (_ownerProfile?.displayName ?? '').isNotEmpty
                                                ? _ownerProfile!.displayName
                                                : 'Seller',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primary,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (sale.description.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            sale.description,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
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

                        // Owner-only destructive action at the very bottom.
                        if (isOwner) ...[
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isDeletingSale ? null : () => _deleteSale(sale.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(_isDeletingSale ? 'Deleting…' : 'Delete Sale'),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
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
            if (_localCoverFile != null)
              Image.file(
                _localCoverFile!,
                fit: BoxFit.cover,
                width: double.infinity,
              )
            else if (hasCover)
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
                            ? 'Uploading... ${(_coverUploadProgress * 100).toInt()}%'
                            : _coverStatusText,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
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
                  setState(() {
                    _localCoverFile = File(image.path);
                  });
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
                  setState(() {
                    _localCoverFile = File(image.path);
                  });
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
      _coverStatusText = 'Uploading...';
    });

    final userId = context.read<AuthService>().currentUser?.id ?? '';
    final url = await FirebaseStorageService.uploadSaleCoverImage(
      imageFile: image,
      saleId: saleId,
      userId: userId,
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
        _localCoverFile = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to upload image. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _coverStatusText = 'Checking image...';
    });

    final updated = await context.read<SalesService>().setSaleCoverPhoto(saleId, url);

    if (!mounted) return;

    setState(() {
      _isCoverUploading = false;
      _coverUploadProgress = 0;
      if (updated != null) {
        _selectedSale = updated;
      } else {
        _localCoverFile = null;
      }
    });

    if (updated == null) {
      final errorMsg = context.read<SalesService>().error ?? 'Failed to save cover photo.';
      final isRejected = errorMsg.toLowerCase().contains('rejected');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRejected
              ? 'Content was deemed UNSAFE and has been removed'
              : errorMsg),
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
