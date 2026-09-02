import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Opens a modal dialog where the currently signed-in user can change their
/// password by entering their current password, a new password, and a
/// confirmation. Uses [authService] defaulting to a fresh [AuthService].
Future<void> showChangePasswordDialog(
  BuildContext context, {
  AuthService? authService,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => ChangePasswordDialog(authService: authService),
  );
}

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key, this.authService});

  final AuthService? authService;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final AuthService _authService;
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirm = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_validateNew(_newCtrl.text) != null) throw const FormatException('');
      await _authService.reauthenticateAndUpdatePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated successfully')),
      );
    } on FirebaseAuthException catch (e) {
      _showError(_mapError(e.code));
    } catch (e) {
      _showError('Failed to update password. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapError(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Current password is incorrect.';
      case 'weak-password':
        return 'Password must be at least 6 characters with an uppercase '
            'letter, a lowercase letter, and a number or symbol.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'requires-recent-login':
        return 'Please log in again before changing your password.';
      default:
        return code;
    }
  }

  String? _validateNew(String? v) {
    if (v == null || v.isEmpty) return 'New password is required';
    if (v.length < 6) return 'Min 6 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v)) {
      return 'Must contain a capital letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(v)) {
      return 'Must contain a lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(v) && !RegExp(r'[^A-Za-z0-9]').hasMatch(v)) {
      return 'Must contain a number or symbol';
    }
    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    required bool hidden,
    required VoidCallback onToggle,
    String? helperText,
    int? helperMaxLines,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: helperMaxLines,
      prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
      suffixIcon: IconButton(
        onPressed: onToggle,
        icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
      ),
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(9))),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        borderSide: BorderSide(color: AppTheme.navy, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Change Password'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentCtrl,
                obscureText: _hideCurrent,
                decoration: _decoration(
                  label: 'Current Password',
                  icon: Icons.lock_outline,
                  hidden: _hideCurrent,
                  onToggle: () => setState(() => _hideCurrent = !_hideCurrent),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Current password is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newCtrl,
                obscureText: _hideNew,
                decoration: _decoration(
                  label: 'New Password',
                  icon: Icons.lock,
                  hidden: _hideNew,
                  onToggle: () => setState(() => _hideNew = !_hideNew),
                  helperText: 'Capital, lowercase, and a number or symbol',
                  helperMaxLines: 2,
                ),
                validator: _validateNew,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _hideConfirm,
                decoration: _decoration(
                  label: 'Confirm New Password',
                  icon: Icons.lock_outline,
                  hidden: _hideConfirm,
                  onToggle: () => setState(() => _hideConfirm = !_hideConfirm),
                ),
                validator: (v) =>
                    v != _newCtrl.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}