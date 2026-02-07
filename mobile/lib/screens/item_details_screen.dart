import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/item.dart';
import '../services/firebase_storage_service.dart';
import '../services/sales_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class ItemDetailsScreen extends StatefulWidget {
  final String saleId;
  final Item item;
  final bool isOwner;

  const ItemDetailsScreen({
    super.key,
    required this.saleId,
    required this.item,
    required this.isOwner,
  });

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  late Item _item;
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late String _category;
  late List<String> _imageUrls;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isDeleting = false;

  int _pageIndex = 0;
  File? _pendingLocalImage;
  String _uploadStatusText = '';
  final PageController _pageController = PageController();

  OutlineInputBorder _outlineBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: 2),
    );
  }

  InputDecoration _fieldDecoration({
    required bool isDarkMode,
    required String labelText,
    String? prefixText,
  }) {
    final base = isDarkMode ? Colors.white24 : Colors.black26;
    final disabled = isDarkMode ? Colors.white12 : Colors.black12;

    return InputDecoration(
      labelText: labelText,
      prefixText: prefixText,
      border: _outlineBorder(base),
      enabledBorder: _outlineBorder(base),
      disabledBorder: _outlineBorder(disabled),
      focusedBorder: _outlineBorder(AppColors.primary),
    );
  }

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _nameController = TextEditingController(text: _item.name);
    _descriptionController = TextEditingController(text: _item.description);
    _priceController = TextEditingController(text: _item.price.toStringAsFixed(2));
    _category = _item.category;
    _imageUrls = List<String>.from(_item.imageUrls);
    _isEditing = widget.isOwner; // owners start in edit mode
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _showImageOptions() async {
    if (!_isEditing || _isSaving || _isDeleting) return;
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
                  await _uploadNewImage(image);
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
                  await _uploadNewImage(image);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadNewImage(XFile image) async {
    final salesService = context.read<SalesService>();

    final totalPages = _imageUrls.length + 1; // +1 for pending local image
    setState(() {
      _pendingLocalImage = File(image.path);
      _isSaving = true;
      _uploadStatusText = 'Uploading...';
    });

    // Auto-scroll to the pending image page after the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          totalPages - 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });

    final userId = context.read<AuthService>().currentUser?.id ?? '';
    final url = await FirebaseStorageService.uploadItemImage(
      imageFile: image,
      saleId: widget.saleId,
      userId: userId,
      itemId: _item.id,
    );

    if (!mounted) return;

    if (url == null || url.isEmpty) {
      setState(() {
        _isSaving = false;
        _pendingLocalImage = null;
        _uploadStatusText = '';
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
      _uploadStatusText = 'Checking image...';
    });

    // Call updateItem so the backend can moderate and persist the new image.
    final newUrls = [..._imageUrls, url];
    final req = CreateItemRequest(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      price: double.tryParse(_priceController.text.trim()) ?? 0,
      imageUrls: newUrls,
      category: _category,
    );

    final updated = await salesService.updateItem(widget.saleId, _item.id, req);

    if (!mounted) return;

    setState(() {
      _isSaving = false;
      _pendingLocalImage = null;
      _uploadStatusText = '';
      if (updated != null) {
        _item = updated;
        _imageUrls = List<String>.from(updated.imageUrls);
      }
    });

    if (updated == null) {
      final errorMsg = salesService.error ?? 'Failed to save image.';
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
          content: Text('Image added!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _removeImageAt(int index) async {
    if (!_isEditing || _isSaving || _isDeleting) return;
    final url = _imageUrls[index];

    setState(() {
      _isSaving = true;
    });

    // Optimistically remove from UI.
    final next = [..._imageUrls]..removeAt(index);
    setState(() {
      _imageUrls = next;
      _pageIndex = _pageIndex.clamp(0, (_imageUrls.length - 1).clamp(0, 9999));
    });

    // Best-effort delete from storage.
    await FirebaseStorageService.deleteImage(url);

    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });
  }

  Future<void> _save() async {
    if (!_isEditing || _isSaving || _isDeleting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final req = CreateItemRequest(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      price: double.tryParse(_priceController.text.trim()) ?? 0,
      imageUrls: _imageUrls,
      category: _category,
    );

    final updated = await context.read<SalesService>().updateItem(
          widget.saleId,
          _item.id,
          req,
        );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (updated != null) {
        _item = updated;
        _imageUrls = List<String>.from(updated.imageUrls);
        _isEditing = widget.isOwner; // stay in edit mode for owners
      }
    });

    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<SalesService>().error ?? 'Failed to save item.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Item updated'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _delete() async {
    if (!widget.isOwner || _isSaving || _isDeleting) return;

    // Capture dependencies before any await gaps to avoid using BuildContext across async gaps.
    final salesService = context.read<SalesService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "${_item.name}"? This cannot be undone.'),
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
    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
    });

    // Delete images first (best-effort), then delete the item record.
    for (final url in _imageUrls) {
      await FirebaseStorageService.deleteImage(url);
    }

    final ok = await salesService.deleteItem(widget.saleId, _item.id);

    if (!mounted) return;

    setState(() {
      _isDeleting = false;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(salesService.error ?? 'Failed to delete item.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (mounted) {
      Navigator.of(context).pop<bool>(true); // deleted
    }
  }

  Widget _buildImagePager(bool isDarkMode) {
    final hasPending = _pendingLocalImage != null;
    final totalCount = _imageUrls.length + (hasPending ? 1 : 0);

    if (totalCount == 0) {
      return Container(
        height: 260,
        color: isDarkMode ? AppColors.darkSurface : AppColors.lightSurface,
        child: Center(
          child: widget.isOwner
              ? ElevatedButton.icon(
                  onPressed: _showImageOptions,
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Add photos'),
                )
              : Icon(
                  Icons.image_outlined,
                  size: 56,
                  color: isDarkMode ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
        ),
      );
    }

    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: totalCount,
            onPageChanged: (i) => setState(() => _pageIndex = i),
            itemBuilder: (context, index) {
              if (index < _imageUrls.length) {
                return CachedNetworkImage(
                  imageUrl: _imageUrls[index],
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
              }
              // Pending local image
              return Image.file(
                _pendingLocalImage!,
                fit: BoxFit.cover,
                width: double.infinity,
              );
            },
          ),
          if (widget.isOwner && _isEditing && !_isSaving)
            Positioned(
              right: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                heroTag: 'add_item_image_${_item.id}',
                onPressed: _showImageOptions,
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.add_a_photo, color: Colors.white),
              ),
            ),
          if (totalCount > 1)
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha((0.55 * 255).round()),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_pageIndex + 1}/$totalCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbnails() {
    if (!widget.isOwner || !_isEditing || _imageUrls.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (oldIndex, newIndex) {
          setState(() {
            final list = [..._imageUrls];
            if (newIndex > oldIndex) newIndex -= 1;
            final item = list.removeAt(oldIndex);
            list.insert(newIndex, item);
            _imageUrls = list;
            _pageIndex = _pageIndex.clamp(0, (_imageUrls.length - 1).clamp(0, 9999));
          });
        },
        children: [
          for (int i = 0; i < _imageUrls.length; i++)
            ListTile(
              key: ValueKey('img_${i}_${_imageUrls[i]}'),
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: _imageUrls[i],
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text(i == 0 ? 'Primary image' : 'Image ${i + 1}'),
              subtitle: const Text('Drag to reorder'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: _isSaving ? null : () => _removeImageAt(i),
                  ),
                  const Icon(Icons.drag_handle),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_item.name),
        actions: [
          if (widget.isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _isDeleting ? null : _delete,
            ),
          if (widget.isOwner)
            IconButton(
              icon: Icon(_isEditing ? Icons.check : Icons.edit),
              onPressed: _isSaving || _isDeleting
                  ? null
                  : () async {
                      if (_isEditing) {
                        await _save();
                      } else {
                        setState(() => _isEditing = true);
                      }
                    },
            ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              children: [
                _buildImagePager(isDarkMode),
                _buildThumbnails(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        enabled: _isEditing,
                        decoration: _fieldDecoration(
                          isDarkMode: isDarkMode,
                          labelText: 'Title',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Title is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        enabled: _isEditing,
                        decoration: _fieldDecoration(
                          isDarkMode: isDarkMode,
                          labelText: 'Description',
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _priceController,
                        enabled: _isEditing,
                        decoration: _fieldDecoration(
                          isDarkMode: isDarkMode,
                          labelText: 'Price',
                          prefixText: '\$',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          final parsed = double.tryParse((v ?? '').trim());
                          if (parsed == null) return 'Enter a valid price';
                          if (parsed < 0) return 'Price cannot be negative';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: _fieldDecoration(
                          isDarkMode: isDarkMode,
                          labelText: 'Category',
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _category,
                            isExpanded: true,
                            onChanged: !_isEditing
                                ? null
                                : (v) => setState(() => _category = v ?? _category),
                            items: ItemCategory.categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Created ${_item.createdAt.toLocal()}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isSaving || _isDeleting)
            Container(
              color: Colors.black.withAlpha((0.25 * 255).round()),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_uploadStatusText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_uploadStatusText, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

