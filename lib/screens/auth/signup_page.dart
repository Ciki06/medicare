import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/role_selector.dart';
import 'auth_layout.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _caregiverEmailController = TextEditingController();
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  UserRole _role = UserRole.patient;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _loading = false;

  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final caregiverEmail = _caregiverEmailController.text.trim();

    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }
    if (password != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _loading = true);
    try {
      String? caregiverId;
      if (_role == UserRole.patient && caregiverEmail.isNotEmpty) {
        final caregiver = await _firestoreService.getUserByEmail(caregiverEmail);
        if (caregiver == null || caregiver.role != UserRole.caregiver) {
          _showError('Caregiver not found with that email');
          setState(() => _loading = false);
          return;
        }
        caregiverId = caregiver.uid;
      }

      await _authService.signUp(
        name: name,
        email: email,
        password: password,
        role: _role,
        caregiverId: caregiverId,
      );

      if (mounted) {
        await _authService.signOut();
        _showSuccessDialog();
      }
      return;
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Sign up failed');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Color(0xFF48AF75), size: 64),
            SizedBox(height: 16),
            Text(
              'Sign Up Successful',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Back to Login'),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _caregiverEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      logoTopSpacing: 5,
      children: [
        const Text(
          'Sign Up For an Account',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5A5A5A),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Full Name',
            hintStyle: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailController,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Email',
            hintStyle: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            prefixIcon: Icon(Icons.email),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passwordController,
          obscureText: _hidePassword,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: const TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            prefixIcon: Icon(Icons.lock),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hidePassword = !_hidePassword),
              icon: Icon(
                _hidePassword ? Icons.visibility : Icons.visibility_off,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _hideConfirmPassword,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Confirm Password',
            hintStyle: const TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            prefixIcon: Icon(Icons.lock),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _hideConfirmPassword = !_hideConfirmPassword),
              icon: Icon(
                _hideConfirmPassword ? Icons.visibility : Icons.visibility_off,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        RoleSelector(
          label: 'Sign Up As:',
          selected: _role,
          onSelected: (role) => setState(() => _role = role),
        ),
        if (_role == UserRole.patient) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _caregiverEmailController,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'Caregiver Email (optional)',
              hintStyle: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
              prefixIcon: Icon(Icons.medical_services),
            ),
          ),
        ],
        const SizedBox(height: 17),
        ElevatedButton(
          onPressed: _loading ? null : _signUp,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Sign Up', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 12),
        AuthFooterLink(
          prompt: 'Already have an account? ',
          action: 'Login',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
