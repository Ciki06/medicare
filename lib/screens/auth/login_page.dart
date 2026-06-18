import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../theme/app_theme.dart';
import '../../widgets/role_selector.dart';
import 'auth_layout.dart';
import 'forgot_password_page.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // final _authService = AuthService();
  UserRole _role = UserRole.patient;
  bool _hidePassword = true;
  bool _isLoading = false;

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        _showError('No account found with this email.');
        return;
      }

      final user = UserModel.fromMap(snap.docs.first.data());
      if (user.role != _role) {
        _showError('This account is registered as ${user.role.label}. '
            'Please select "${user.role.label}" to log in.');
        return;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      _showError(_mapAuthError(e.code));
    } catch (e) {
      _showError('An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      default:
        return 'Login failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      logoTopSpacing: 10,
      children: [
        TextField(
          key: const Key('login-email'),
          controller: _emailController,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Username or Email',
            hintStyle: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('login-password'),
          controller: _passwordController,
          obscureText: _hidePassword,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            prefixIcon: Icon(Icons.lock),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hidePassword = !_hidePassword),
              icon: Icon(
                _hidePassword ? Icons.visibility : Icons.visibility_off,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _open(const ForgotPasswordPage()),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE3882E),
              padding: const EdgeInsets.symmetric(vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Forgot Password?',
              style: TextStyle(
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        RoleSelector(
          selected: _role,
          onSelected: (role) => setState(() => _role = role),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          key: const Key('login-button'),
          onPressed: _isLoading ? null : _login,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Login', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => _open(const SignUpPage()),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.green,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
          ),
          child: const Text(
            'Create Account',
            style: TextStyle(
              fontSize: 13,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
