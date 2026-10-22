import 'package:flutter/material.dart';
import '../../services/password_reset_service.dart';
import 'auth_layout.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({
    super.key,
    required this.verified,
    required this.service,
  });
  final VerifiedPasswordReset verified;
  final PasswordResetGateway service;
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _hidePassword = true, _hideConfirm = true, _loading = false;
  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await widget.service.resetPassword(widget.verified, _password.text);
      if (!mounted) return;
      _password.clear();
      _confirm.clear();
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).clearSnackBars();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(
            Icons.check_circle,
            color: Color(0xFF61A654),
            size: 50,
          ),
          title: const Text('Password Reset Successful'),
          content: const Text(
            'You can now sign in with your new password.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('Back to login'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PasswordResetFailure
                  ? error.message
                  : 'Could not reset the password. Please try again.',
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
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    children: [
      const Text(
        'Reset Password',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 14),
      Text(
        'Your email has been verified. Set a new password for ${widget.verified.email}.',
        style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 18),
      Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              key: const ValueKey('reset-new-password'),
              controller: _password,
              enabled: !_loading,
              obscureText: _hidePassword,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'New Password',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) => (value?.length ?? 0) >= 6
                  ? null
                  : 'Use at least 6 characters.',
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey('reset-confirm-password'),
              controller: _confirm,
              enabled: !_loading,
              obscureText: _hideConfirm,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Confirm New Password',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _hideConfirm = !_hideConfirm),
                  icon: Icon(
                    _hideConfirm ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) =>
                  value == _password.text ? null : 'Passwords do not match.',
              onFieldSubmitted: (_) {
                if (!_loading) {
                  _reset();
                }
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      ElevatedButton(
        onPressed: _loading ? null : _reset,
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
            : const Text('Reset password', style: TextStyle(fontSize: 16)),
      ),
      const SizedBox(height: 12),
      AuthFooterLink(
        prompt: 'Remember your password? ',
        action: 'Login',
        onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
    ],
  );
}
