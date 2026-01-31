import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ConfirmDeleteAccountScreen extends StatefulWidget {
  const ConfirmDeleteAccountScreen({super.key});

  @override
  State<ConfirmDeleteAccountScreen> createState() => _ConfirmDeleteAccountScreenState();
}

class _ConfirmDeleteAccountScreenState extends State<ConfirmDeleteAccountScreen> {
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _confirmController.text.trim().toUpperCase() == 'DELETE';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete account'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This will permanently delete your account and all sales you created.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'This cannot be undone.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _confirmController,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: canDelete ? () => Navigator.of(context).pop(true) : null,
                child: const Text('Delete account'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

