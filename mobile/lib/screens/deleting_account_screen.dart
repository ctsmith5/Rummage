import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/firebase_storage_service.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';
import 'auth/login_screen.dart';

class DeletingAccountScreen extends StatefulWidget {
  const DeletingAccountScreen({super.key});

  @override
  State<DeletingAccountScreen> createState() => _DeletingAccountScreenState();
}

class _DeletingAccountScreenState extends State<DeletingAccountScreen> {
  String? _error;
  bool _started = false;

  Future<String?> _promptPasswordForReauth() async {
    final controller = TextEditingController();
    try {
      final value = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm password'),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Continue')),
          ],
        ),
      );
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _runDelete() async {
    try {
      // 1) Delete backend data and get image URLs to delete
      final urls = await context.read<ProfileService>().deleteAccount();

      // 2) Best-effort delete Firebase Storage assets
      for (final u in urls) {
        if (u.trim().isEmpty) continue;
        await FirebaseStorageService.deleteImage(u);
      }

      // 3) Delete Firebase Auth user (reauth if required)
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await user.delete();
        } on fb.FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            final email = user.email;
            if (email == null || email.isEmpty) rethrow;
            final password = await _promptPasswordForReauth();
            if (password == null) rethrow;
            final cred = fb.EmailAuthProvider.credential(email: email, password: password);
            await user.reauthenticateWithCredential(cred);
            await user.delete();
          } else {
            rethrow;
          }
        }
      }

      // 4) Sign out locally and return to login
      await context.read<AuthService>().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to delete account. Please try again.';
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _runDelete());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Deleting account'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _error == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        SizedBox(height: 14),
                        Text('Deleting your account…'),
                        SizedBox(height: 6),
                        Text(
                          'This may take a few seconds.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 40),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _error = null);
                            _runDelete();
                          },
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

