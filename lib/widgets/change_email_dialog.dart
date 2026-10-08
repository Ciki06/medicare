import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/managed_account_service.dart';
import '../theme/app_theme.dart';

/// Opens a dialog where the signed-in caregiver changes the email on their own
/// account. Firebase only applies the new address once the confirmation link it
/// emails is opened, so a mistyped address cannot lock them out. Returns true
/// when a confirmation link was sent.
Future<bool> showChangeEmailDialog(
  BuildContext context, {
  required String currentEmail,
  AuthService? authService,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => ChangeEmailDialog(
      currentEmail: currentEmail,
      authService: authService,
    ),
  );
  return sent ?? false;
}

/// Opens a dialog where a caregiver repoints the sign-in email of an account
/// they manage. The caregiver's own password is confirmed because the new
/// address is applied immediately. Returns true when it was updated.
Future<bool> showManagedAccountEmailDialog(
  BuildContext context, {
  required UserModel account,
  ManagedAccountService? service,
}) async {
  final updated = await showDialog<bool>(
    context: context,
    builder: (_) => ChangeEmailDialog(
      targetUid: account.uid,
      currentEmail: account.email,
      accountName: account.name,
      authService: AuthService(),
      service: service,
    ),
  );
  return updated ?? false;
}

class ChangeEmailDialog extends StatefulWidget {
  const ChangeEmailDialog({
    super.key,
    required this.currentEmail,
    this.targetUid,
    this.accountName,
    this.authService,
    this.service,
  });

  final String currentEmail;

  /// Set when a caregiver is editing an account they manage instead of their
  /// own; the address then changes immediately rather than after a
  /// confirmation link.
  final String? targetUid;
  final String? accountName;
  final AuthService? authService;
  final ManagedAccountService? service;

  bool get isManagedAccount => targetUid != null;

  @override
  State<ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<ChangeEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  late final AuthService _authService;
  late final ManagedAccountService _service;
  late final TextEditingController _emailCtrl;
  final _passwordCtrl = TextEditingController();
  bool _hidePassword = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _service = widget.service ?? ManagedAccountService();
    _emailCtrl = TextEditingController(text: widget.currentEmail);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Email is required';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email == widget.currentEmail.toLowerCase()) {
      _showError('That is already the current email address.');
      return;
    }
    setState(() => _loading = true);
    try {
      if (widget.isManagedAccount) {
        await _service.updateEmail(
          uid: widget.targetUid!,
          email: email,
          caregiverPassword: _passwordCtrl.text,
        );
      } else {
        await _authService.changeEmail(
          currentPassword: _passwordCtrl.text,
          newEmail: email,
        );
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.isManagedAccount
                ? 'Email updated to $email'
                : 'Confirmation link sent to $email',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      _showError(_mapAuthError(e.code));
    } catch (e) {
      _showError('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Current password is incorrect.';
      case 'email-already-exists':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'requires-recent-login':
        return 'Please log in again before changing your email.';
      default:
        return 'Could not change the email address.';
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? helperText,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
      suffixIcon: suffix,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
      ),
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
      title: Text(
        widget.isManagedAccount
            ? 'Change Email for ${widget.accountName ?? 'Account'}'
            : 'Change Email',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isManagedAccount
                    ? 'This address becomes the sign-in email for this account.'
                    : 'A confirmation link is sent to the new address, which '
                        'only changes once it is opened.',
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                decoration: _decoration(
                  label: 'Email',
                  icon: Icons.email,
                ),
                validator: _validateEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                enabled: !_loading,
                obscureText: _hidePassword,
                decoration: _decoration(
                  label: 'Your Current Password',
                  icon: Icons.lock_outline,
                  helperText: 'Required to confirm the change',
                  suffix: IconButton(
                    onPressed: () =>
                        setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(
                      _hidePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Password is required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}