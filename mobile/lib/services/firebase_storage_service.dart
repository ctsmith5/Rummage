import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Service for uploading images to Firebase Storage
class FirebaseStorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static String? lastUploadError;

  static String _contentTypeForExtension(String ext) {
    final e = ext.toLowerCase();
    if (e == 'png') return 'image/png';
    if (e == 'webp') return 'image/webp';
    if (e == 'gif') return 'image/gif';
    return 'image/jpeg';
  }

  static String _formatFirebaseStorageError(Object e) {
    if (e is FirebaseException) {
      final msg = e.message?.trim();
      return 'FirebaseStorage (${e.code})${msg != null && msg.isNotEmpty ? ': $msg' : ''}';
    }
    return e.toString();
  }

  /// Upload a sale cover photo to Firebase Storage.
  /// Returns the download URL of the uploaded image.
  static Future<String?> uploadSaleCoverImage({
    required XFile imageFile,
    required String saleId,
    required String userId,
    void Function(double progress)? onProgress,
  }) async {
    try {
      lastUploadError = null;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = imageFile.path.split('.').last;
      final filename = 'cover_$timestamp.$extension';

      // Upload to quarantine path. A server-side worker promotes to the approved path after SafeSearch.
      final ref = _storage.ref().child('pending/sales/$saleId/cover/$filename');

      final bytes = await imageFile.readAsBytes();
      debugPrint(
        'Uploading sale cover: saleId=$saleId file=${imageFile.path} bytes=${bytes.length} dest=${ref.fullPath}',
      );
      final metadata = SettableMetadata(
        contentType: _contentTypeForExtension(extension),
        customMetadata: {
          'userId': userId,
          'saleId': saleId,
          'type': 'sale_cover',
          'moderation': 'pending',
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      final uploadTask = ref.putData(bytes, metadata);
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);
        });
      }

      final snapshot = await uploadTask;
      debugPrint(
        'Sale cover upload finished (pending): state=${snapshot.state} bytes=${snapshot.bytesTransferred}/${snapshot.totalBytes}',
      );
      // Return storage path; the backend/worker will promote and attach an approved URL later.
      return ref.fullPath;
    } catch (e, st) {
      final formatted = _formatFirebaseStorageError(e);
      lastUploadError = formatted;
      debugPrint('Error uploading sale cover image: $formatted');
      debugPrint('Stack trace: $st');
      return null;
    }
  }

  /// Upload an image file to Firebase Storage
  /// Returns the download URL of the uploaded image
  static Future<String?> uploadItemImage({
    required XFile imageFile,
    required String saleId,
    required String userId,
    String? itemId,
    void Function(double progress)? onProgress,
  }) async {
    try {
      // Generate a unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = imageFile.path.split('.').last;
      final filename = '${itemId ?? "item"}_$timestamp.$extension';

      // Create storage reference
      final ref = _storage.ref().child('pending/sales/$saleId/items/$filename');

      // Read file bytes
      final bytes = await imageFile.readAsBytes();

      // Create upload metadata
      final metadata = SettableMetadata(
        contentType: _contentTypeForExtension(extension),
        customMetadata: {
          'userId': userId,
          'saleId': saleId,
          if (itemId != null) 'itemId': itemId,
          'type': 'sale_item',
          'moderation': 'pending',
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      // Upload the file
      final uploadTask = ref.putData(bytes, metadata);

      // Listen to progress if callback provided
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);
        });
      }

      // Wait for upload to complete
      final snapshot = await uploadTask;

      debugPrint('Item image uploaded successfully (pending): ${ref.fullPath}');
      return ref.fullPath;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  /// Upload a user profile photo to Firebase Storage.
  /// Returns the download URL of the uploaded image.
  static Future<String?> uploadProfileImage({
    required XFile imageFile,
    required String userId,
    void Function(double progress)? onProgress,
  }) async {
    try {
      lastUploadError = null;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = imageFile.path.split('.').last;
      final filename = 'profile_$timestamp.$extension';

      final ref = _storage.ref().child('pending/users/$userId/profile/$filename');

      final bytes = await imageFile.readAsBytes();
      debugPrint(
        'Uploading profile photo: userId=$userId file=${imageFile.path} bytes=${bytes.length} dest=${ref.fullPath}',
      );
      final metadata = SettableMetadata(
        contentType: _contentTypeForExtension(extension),
        customMetadata: {
          'userId': userId,
          'type': 'profile_photo',
          'moderation': 'pending',
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      final uploadTask = ref.putData(bytes, metadata);
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);
        });
      }

      final snapshot = await uploadTask;
      debugPrint('Profile photo uploaded successfully (pending): state=${snapshot.state} path=${ref.fullPath}');
      return ref.fullPath;
    } catch (e, st) {
      final formatted = _formatFirebaseStorageError(e);
      lastUploadError = formatted;
      debugPrint('Error uploading profile photo: $formatted');
      debugPrint('Stack trace: $st');
      return null;
    }
  }

  /// Upload an image from file path
  static Future<String?> uploadFromPath({
    required String filePath,
    required String saleId,
    required String userId,
    String? itemId,
    void Function(double progress)? onProgress,
  }) async {
    final file = XFile(filePath);
    return uploadItemImage(
      imageFile: file,
      saleId: saleId,
      userId: userId,
      itemId: itemId,
      onProgress: onProgress,
    );
  }

  /// Delete an image from Firebase Storage
  static Future<bool> deleteImage(String imageUrl) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
      debugPrint('Image deleted successfully');
      return true;
    } catch (e) {
      debugPrint('Error deleting image: $e');
      return false;
    }
  }

  /// Get a list of all images for a sale
  static Future<List<String>> getSaleImages(String saleId) async {
    try {
      final ref = _storage.ref().child('sales/$saleId/items');
      final result = await ref.listAll();
      
      final urls = <String>[];
      for (final item in result.items) {
        final url = await item.getDownloadURL();
        urls.add(url);
      }
      
      return urls;
    } catch (e) {
      debugPrint('Error listing sale images: $e');
      return [];
    }
  }
}


