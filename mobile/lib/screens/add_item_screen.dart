import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/sales_service.dart';
import '../services/firebase_storage_service.dart';
import '../theme/app_colors.dart';

class AddItemScreen extends StatefulWidget {
  final String saleId;

  const AddItemScreen({
    super.key,
    required this.saleId,
  });

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();

  String _selectedCategory = 'Other';
  XFile? _selectedImage;
  bool _isLoading = false;
  double _uploadProgress = 0;
  String _loadingMessage = '';

  final ImagePicker _imagePicker = ImagePicker();

  OutlineInputBorder _outlineBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: 2),
    );
  }

  InputDecoration _fieldDecoration({
    required bool isDarkMode,
    required String labelText,
    String? hintText,
    String? prefixText,
  }) {
    final base = isDarkMode ? Colors.white24 : Colors.black26;
    final disabled = isDarkMode ? Colors.white12 : Colors.black12;

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      border: _outlineBorder(base),
      enabledBorder: _outlineBorder(base),
      disabledBorder: _outlineBorder(disabled),
      focusedBorder: _outlineBorder(AppColors.primary),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<void> _takePhoto() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            if (_selectedImage != null)
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('Remove Photo'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Capture dependencies before any await gaps to avoid using BuildContext across async gaps.
    final salesService = context.read<SalesService>();

    setState(() {
      _isLoading = true;
      _uploadProgress = 0;
      _loadingMessage = 'Preparing...';
    });

    String imageUrl = '';

    // Upload image to Firebase Storage if selected
    if (_selectedImage != null) {
      setState(() {
        _loadingMessage = 'Uploading image...';
      });

      final userId = context.read<AuthService>().currentUser?.id ?? '';
      imageUrl = await FirebaseStorageService.uploadItemImage(
        imageFile: _selectedImage!,
        saleId: widget.saleId,
        userId: userId,
        onProgress: (progress) {
          setState(() {
            _uploadProgress = progress;
          });
        },
      ) ?? '';

      if (imageUrl.isEmpty && mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to upload image. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    setState(() {
      _loadingMessage = 'Checking image...';
    });

    final request = CreateItemRequest(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      price: double.tryParse(_priceController.text) ?? 0,
      imageUrls: imageUrl.isNotEmpty ? [imageUrl] : [],
      category: _selectedCategory,
    );

    final item = await salesService.addItem(
      widget.saleId,
      request,
    );

    setState(() {
      _isLoading = false;
    });

    if (item != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item added successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      // Return `true` so the Sale Details screen can refresh immediately.
      Navigator.of(context).pop(true);
    } else if (mounted) {
      final errorMsg = salesService.error ?? 'Failed to add item. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMsg.toLowerCase().contains('rejected')
                ? 'Photo rejected — violates community guidelines'
                : errorMsg,
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Item'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Image picker
            GestureDetector(
              onTap: _showImageOptions,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? AppColors.darkSurface
                      : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDarkMode
                        ? AppColors.darkCard
                        : Colors.grey.shade300,
                  ),
                ),
                child: _selectedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_selectedImage!.path),
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo,
                            size: 48,
                            color: isDarkMode
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add Photo',
                            style: TextStyle(
                              color: isDarkMode
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // Name
            TextFormField(
              controller: _nameController,
              decoration: _fieldDecoration(
                isDarkMode: isDarkMode,
                labelText: 'Item Name',
                hintText: 'e.g., Vintage Chair, Table Lamp',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an item name';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: _fieldDecoration(
                isDarkMode: isDarkMode,
                labelText: 'Description',
                hintText: 'Describe the item condition, size, etc.',
              ),
              maxLines: 3,
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 16),

            // Price
            TextFormField(
              controller: _priceController,
              decoration: _fieldDecoration(
                isDarkMode: isDarkMode,
                labelText: 'Price',
                prefixText: '\$ ',
                hintText: '0.00',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final price = double.tryParse(value);
                  if (price == null || price < 0) {
                    return 'Please enter a valid price';
                  }
                }
                return null;
              },
              textInputAction: TextInputAction.done,
            ),

            const SizedBox(height: 16),

            // Category
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: _fieldDecoration(
                isDarkMode: isDarkMode,
                labelText: 'Category',
              ),
              items: ItemCategory.categories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedCategory = value;
                  });
                }
              },
            ),

            const SizedBox(height: 32),

            // Submit button
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: _uploadProgress > 0 ? _uploadProgress : null,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _uploadProgress > 0
                              ? '${(_uploadProgress * 100).toInt()}%'
                              : _loadingMessage,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    )
                  : const Text('Add Item'),
            ),
          ],
        ),
      ),
    );
  }
}

