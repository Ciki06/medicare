import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import '../../widgets/role_selector.dart';
import 'auth_layout.dart';
import 'reset_password_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  UserRole _role = UserRole.patient;
  bool _loading = false;

  void _detectRole(String value) {
    final lower = value.toLowerCase();
    setState(() {
      if (lower.contains('care')) {
        _role = UserRole.caregiver;
      } else if (lower.contains('family')) {
        _role = UserRole.family;
      } else if (lower.contains('pharm')) {
        _role = UserRole.pharmacist;
      } else {
        _role = UserRole.patient;
      }
    });
  }

  Future<void> _sendReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ResetPasswordPage(role: _role, email: email),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      children: [
        const Text(
          'Forgot Password',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _emailController,
          onChanged: _detectRole,
          decoration: const InputDecoration(
            hintText: 'Email',
            prefixIcon: Icon(Icons.email),
          ),
        ),
        const SizedBox(height: 14),
        RoleSelector(
          label: 'Account Type',
          selected: _role,
          onSelected: (role) => setState(() => _role = role),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _loading ? null : _sendReset,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF61A654),
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Next', style: TextStyle(fontSize: 16)),
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
