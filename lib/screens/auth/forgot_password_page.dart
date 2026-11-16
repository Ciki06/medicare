import 'package:flutter/material.dart';
import '../../services/password_reset_service.dart';
import '../../services/email_policy.dart';
import 'auth_layout.dart';
import 'verify_reset_code_page.dart';

/// Starts password recovery by requesting a code for the user's email.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.service});
  final PasswordResetGateway? service;
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  // Track the email, form validation, and request state.
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final PasswordResetGateway _service;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    // Use the supplied reset service or fall back to Firebase.
    _service = widget.service ?? FirebasePasswordResetService();
  }

  // Check the email before requesting a code.
  Future<void> _sendCode() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final challenge = await _service.requestCode(_email.text);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        // Pass the reset challenge to the code entry screen.
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                VerifyResetCodePage(challenge: challenge, service: _service),
          ),
        );
      }
    // Show the service error when available.
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
    // Enable the form again when the request finishes.
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    // Release the email controller when leaving the page.
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    logoTopSpacing: 10,
    logoSize: (MediaQuery.sizeOf(context).shortestSide * 0.48)
        .clamp(144.0, 180.0)
        .toDouble(),
    topPadding: 32,
    children: [
      const Text(
        'Forgot Password',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 14),
      // Collect and validate the registered email address.
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
            helperText:
                'Enter your registered email address to receive a four-digit verification code.',
            helperMaxLines: 6,
            helperStyle: TextStyle(fontSize: 12, color: Color(0xFF666666)),
            prefixIcon: Icon(Icons.email),
          ),
          validator: EmailPolicy.validate,
          onFieldSubmitted: (_) {
            if (!_loading) {
              _sendCode();
            }
          },
        ),
      ),
      const SizedBox(height: 18),
      // Disable sending while the code request is running.
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
      // Return to sign-in.
      AuthFooterLink(
        prompt: 'Remember your password? ',
        action: 'Login',
        onTap: () => Navigator.of(context).pop(),
      ),
    ],
  );
}
