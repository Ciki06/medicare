import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import 'auth_layout.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.role, this.email});

  final UserRole role;
  final String? email;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _codeController = TextEditingController();
  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _loading = false;

  Future<void> _reset() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final email = widget.email;
      if (email == null) return;
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            icon: const Icon(Icons.check_circle, color: Color(0xFF61A654), size: 50),
            title: const Text('Password Reset Email Sent'),
            content: const Text('Check your email to reset your password.', textAlign: TextAlign.center),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Failed'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      children: [
        const Text(
          'Reset Password',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        const Text(
          'A password reset link has been sent to your email.',
          style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          obscureText: _hidePassword,
          decoration: InputDecoration(
            hintText: 'New Password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hidePassword = !_hidePassword),
              icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _confirmController,
          obscureText: _hideConfirm,
          decoration: InputDecoration(
            hintText: 'Confirm New Password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hideConfirm = !_hideConfirm),
              icon: Icon(_hideConfirm ? Icons.visibility : Icons.visibility_off),
            ),
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _loading ? null : _reset,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF61A654)),
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Send Reset Link', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 12),
        AuthFooterLink(
          prompt: 'Remember your password? ',
          action: 'Login',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
