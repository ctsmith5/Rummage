import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../app_nav.dart';
import '../services/auth_service.dart';
import '../services/firebase_storage_service.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';
import 'auth/login_screen.dart';
import 'confirm_delete_account_screen.dart';
import 'deleting_account_screen.dart';

class ProfileScreen extends StatefulWidget {
  final Profile? initialProfile;
  const ProfileScreen({super.key, this.initialProfile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _bioController = TextEditingController();
  final _nameController = TextEditingController();
  DateTime? _dob;
  String _photoUrl = '';
  bool _saving = false;
  bool _deleting = false;
  File? _localPhotoFile;
  String _photoUploadStatus = '';

  @override
  void dispose() {
    _bioController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  int _ageFromDob(DateTime dob) {
    final now = DateTime.now();
    var years = now.year - dob.year;
    final hadBirthdayThisYear = (now.month > dob.month) || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) years -= 1;
    return years;
  }

  DateTime _cutoff16() {
    final now = DateTime.now();
    return DateTime(now.year - 16, now.month, now.day);
  }

  Future<void> _load() async {
    final svc = context.read<ProfileService>();
    await svc.loadProfile();
    final p = svc.profile;
    if (!mounted || _deleting || p == null) return;
    setState(() {
      _nameController.text = p.displayName;
      _bioController.text = p.bio;
      _dob = p.dob;
      _photoUrl = p.photoUrl;
      _localPhotoFile = null;
    });
  }

  void _seedFrom(Profile p) {
    _nameController.text = p.displayName;
    _bioController.text = p.bio;
    _dob = p.dob;
    _photoUrl = p.photoUrl;
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1970, 1, 1),
      firstDate: DateTime(1900, 1, 1),
      lastDate: _cutoff16(),
      helpText: 'Select date of birth',
    );
    if (picked == null) return;
    setState(() {
      _dob = picked;
    });
  }

  Future<void> _save() async {
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set your date of birth')),
      );
      return;
    }
    if (_ageFromDob(_dob!) < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be 16 years old or older')),
      );
      return;
    }

    setState(() => _saving = true);
    final ok = await context.read<ProfileService>().updateProfile(
          displayName: _nameController.text.trim(),
          bio: _bioController.text.trim(),
          dob: _dob,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save profile')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final authUser = fb.FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (file == null) return;

    setState(() {
      _localPhotoFile = File(file.path);
      _saving = true;
      _photoUploadStatus = 'Uploading...';
    });

    final url = await FirebaseStorageService.uploadProfileImage(
      imageFile: file,
      userId: authUser.uid,
    );
    if (!mounted) return;
    if (url == null) {
      setState(() {
        _saving = false;
        _localPhotoFile = null;
        _photoUploadStatus = '';
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
      _photoUploadStatus = 'Checking image...';
    });

    final ok = await context.read<ProfileService>().updateProfile(photoUrl: url);
    if (!mounted) return;

    if (!ok) {
      final errorMsg = context.read<ProfileService>().error ?? '';
      final isRejected = errorMsg.toLowerCase().contains('rejected');
      setState(() {
        _saving = false;
        _localPhotoFile = null;
        _photoUploadStatus = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRejected
              ? 'Content was deemed UNSAFE and has been removed'
              : 'Failed to save profile photo'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final p = context.read<ProfileService>().profile;
    setState(() {
      _saving = false;
      _photoUploadStatus = '';
      if (p != null) _photoUrl = p.photoUrl;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile photo updated!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    // Error state variables - using a Map so we can modify from _changePassword
    final errors = <String, String?>{
      'current': null,
      'new': null,
      'confirm': null,
    };

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Real-time validation logic
            void validateFields() {
              setDialogState(() {
                // Clear previous errors
                errors['current'] = null;
                errors['new'] = null;
                errors['confirm'] = null;

                final current = currentPasswordController.text;
                final newPwd = newPasswordController.text;
                final confirm = confirmPasswordController.text;

                // Validate new password length (only if user has typed something)
                if (newPwd.isNotEmpty && newPwd.length < 8) {
                  errors['new'] = 'At least 8 characters required';
                }

                // Validate password match (only if user has typed in confirm field)
                if (confirm.isNotEmpty && newPwd != confirm) {
                  errors['confirm'] = 'Passwords do not match';
                }

                // Validate new password is different from current (only if both are filled)
                if (current.isNotEmpty && newPwd.isNotEmpty && current == newPwd) {
                  errors['new'] = 'Must be different from current password';
                }
              });
            }

            // Computed validation state
            bool isValid() {
              final current = currentPasswordController.text;
              final newPwd = newPasswordController.text;
              final confirm = confirmPasswordController.text;

              // All fields must have content
              if (current.isEmpty || newPwd.isEmpty || confirm.isEmpty) return false;

              // New password must be at least 8 chars
              if (newPwd.length < 8) return false;

              // Passwords must match
              if (newPwd != confirm) return false;

              // New password must be different
              if (current == newPwd) return false;

              return true;
            }

            return AlertDialog(
              title: const Text('Change Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Current password field
                    TextField(
                      controller: currentPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Current password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: errors['current'],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureCurrent
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureCurrent = !obscureCurrent;
                            });
                          },
                        ),
                      ),
                      obscureText: obscureCurrent,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => validateFields(),
                    ),
                    const SizedBox(height: 16),

                    // New password field
                    TextField(
                      controller: newPasswordController,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        helperText: 'At least 8 characters',
                        errorText: errors['new'],
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureNew
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureNew = !obscureNew;
                            });
                          },
                        ),
                      ),
                      obscureText: obscureNew,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => validateFields(),
                    ),
                    const SizedBox(height: 16),

                    // Confirm password field
                    TextField(
                      controller: confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        errorText: errors['confirm'],
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureConfirm = !obscureConfirm;
                            });
                          },
                        ),
                      ),
                      obscureText: obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => validateFields(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isValid()
                      ? () async {
                          await _changePassword(
                            dialogContext,
                            setDialogState,
                            errors,
                            currentPasswordController.text,
                            newPasswordController.text,
                            confirmPasswordController.text,
                          );
                        }
                      : null,
                  child: const Text('Change Password'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      // Defer controller disposal until after dialog is fully disposed
      WidgetsBinding.instance.addPostFrameCallback((_) {
        currentPasswordController.dispose();
        newPasswordController.dispose();
        confirmPasswordController.dispose();
      });
    });
  }

  Future<void> _changePassword(
    BuildContext dialogContext,
    StateSetter setDialogState,
    Map<String, String?> errors,
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('Not authenticated');
      }

      // Step 1: Re-authenticate with current password
      final credential = fb.EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // Step 2: Update password
      await user.updatePassword(newPassword);

      if (!mounted) return;

      // Close dialog on success
      Navigator.of(dialogContext).pop();

      // FIXED: Schedule SnackBar for next frame to avoid disposal race condition
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password changed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      });
    } on fb.FirebaseAuthException catch (e) {
      if (!mounted) return;

      // Show inline error for wrong password - keep dialog open
      if (e.code == 'wrong-password') {
        setDialogState(() {
          errors['current'] = 'Incorrect existing password';
        });
      } else {
        // For other Firebase errors, still use SnackBar (rare cases)
        String errorMessage;
        switch (e.code) {
          case 'weak-password':
            errorMessage = 'New password is too weak';
            break;
          case 'requires-recent-login':
            errorMessage = 'Please log out and log back in before changing password';
            break;
          default:
            errorMessage = 'Failed to change password: ${e.message ?? 'Unknown error'}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to change password. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteAccount() async {
    // Confirm using a full-screen route (not dialogs) to avoid Overlay teardown races.
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final proceed = await nav.push<bool>(
          MaterialPageRoute(builder: (_) => const ConfirmDeleteAccountScreen()),
        ) ??
        false;
    if (!proceed) return;

    // Move to a dedicated screen via the ROOT navigator so we don't depend on a context
    // that is being disposed (prevents Overlay/_Theater GlobalKey teardown errors).
    if (!mounted) return;
    setState(() => _deleting = true);
    FocusScope.of(context).unfocus();
    appScaffoldMessengerKey.currentState?.clearSnackBars();

    nav.pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const DeletingAccountScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    // Seed immediately if HomeScreen prefetched profile (prevents "empty then populate" flash).
    final seeded = widget.initialProfile;
    if (seeded != null) {
      _seedFrom(seeded);
    }

    // Ensure profile is loaded/refreshed; if already loaded this is fast.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _deleting) return;
      final svc = context.read<ProfileService>();
      if (svc.profile == null) {
        await _load();
      } else if (widget.initialProfile == null) {
        // If not seeded via navigation, populate from provider immediately.
        final p = svc.profile;
        if (p != null && mounted) {
          setState(() => _seedFrom(p));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Avoid subscribing to Provider updates here; during account deletion the provider can notify
    // while this route is being torn down, leading to rebuild/listener churn.
    final dob = _dob;
    final age = dob != null ? _ageFromDob(dob) : null;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDarkMode ? Colors.white12 : Colors.black12;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: InkWell(
                  onTap: _saving ? null : _pickAndUploadPhoto,
                  borderRadius: BorderRadius.circular(60),
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.lightSurface,
                    backgroundImage: _localPhotoFile != null
                        ? FileImage(_localPhotoFile!) as ImageProvider
                        : (_photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null),
                    child: _localPhotoFile == null && _photoUrl.isEmpty
                        ? const Icon(Icons.person, size: 42, color: AppColors.primary)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _saving ? null : _pickAndUploadPhoto,
                  child: const Text('Change photo'),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  prefixIcon: Icon(Icons.person_outlined),
                ),
                textCapitalization: TextCapitalization.words,
                enabled: !_saving,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
              ),
              const SizedBox(height: 16),

              InkWell(
                onTap: _saving ? null : _pickDob,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date of birth',
                    prefixIcon: Icon(Icons.cake_outlined),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dob != null
                            ? '${dob.month.toString().padLeft(2, '0')}/${dob.day.toString().padLeft(2, '0')}/${dob.year}'
                            : 'Select',
                      ),
                      if (age != null) Text('Age $age'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const Text('Saving…') : const Text('Save'),
              ),

              const SizedBox(height: 12),

              // Change password button
              OutlinedButton.icon(
                onPressed: _saving ? null : _showChangePasswordDialog,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Change password'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),

              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        await context.read<AuthService>().logout();
                        if (!mounted) return;
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text('Log Out'),
              ),

              const SizedBox(height: 24),
              Divider(color: dividerColor),
              const SizedBox(height: 8),
              Text(
                'Danger zone',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: _saving ? null : _deleteAccount,
                child: const Text('Delete account'),
              ),
            ],
          ),
        ),
            if (_saving && _photoUploadStatus.isNotEmpty)
              Container(
                color: Colors.black.withAlpha((0.25 * 255).round()),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(_photoUploadStatus, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

