import 'package:flutter/material.dart';
import '../../services/password_reset_service.dart';
import 'auth_layout.dart';
import 'verify_reset_code_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.service});
  final PasswordResetGateway? service;
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final PasswordResetGateway _service;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FirebasePasswordResetService();
  }

  Future<void> _sendCode() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final challenge = await _service.requestCode(_email.text);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                VerifyResetCodePage(challenge: challenge, service: _service),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PasswordResetFailure
                  ? error.message
                  : 'Could not send the code. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    children: [
      const Text(
        'Forgot Password',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 14),
      const Text(
        'Enter your registered email address to receive a four-digit verification code.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
      ),
      const SizedBox(height: 18),
      Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey('reset-email'),
          controller: _email,
          enabled: !_loading,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'Email',
            prefixIcon: Icon(Icons.email),
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            return email.length <= 254 &&
                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                ? null
                : 'Enter a valid email address.';
          },
          onFieldSubmitted: (_) {
            if (!_loading) {
              _sendCode();
            }
          },
        ),
      ),
      const SizedBox(height: 18),
      ElevatedButton(
        onPressed: _loading ? null : _sendCode,
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
            : const Text('Send code', style: TextStyle(fontSize: 16)),
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
