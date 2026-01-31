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
    });
  }

  void _seedFrom(Profile p) {
    _nameController.text = p.displayName;
    _bioController.text = p.bio;
    _dob = p.dob;
    _photoUrl = p.photoUrl;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
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

    setState(() => _saving = true);
    final url = await FirebaseStorageService.uploadProfileImage(
      imageFile: file,
      userId: authUser.uid,
    );
    if (!mounted) return;
    if (url == null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirebaseStorageService.lastUploadError ?? 'Failed to upload photo')),
      );
      return;
    }

    final ok = await context.read<ProfileService>().updateProfile(photoUrl: url);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save profile photo')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile photo submitted for review. It will appear once approved.')),
    );
    final p = context.read<ProfileService>().profile;
    if (p != null) {
      setState(() {
        _photoUrl = p.photoUrl;
      });
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
        child: SingleChildScrollView(
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
                    backgroundImage: _photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null,
                    child: _photoUrl.isEmpty
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
      ),
    );
  }
}

