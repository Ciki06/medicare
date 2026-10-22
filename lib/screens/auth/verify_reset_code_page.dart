import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/password_reset_service.dart';
import 'auth_layout.dart';
import 'reset_password_page.dart';

class VerifyResetCodePage extends StatefulWidget {
  const VerifyResetCodePage({
    super.key,
    required this.challenge,
    required this.service,
  });
  final PasswordResetChallenge challenge;
  final PasswordResetGateway service;
  @override
  State<VerifyResetCodePage> createState() => _VerifyResetCodePageState();
}

class _VerifyResetCodePageState extends State<VerifyResetCodePage> {
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  late PasswordResetChallenge _challenge;
  Timer? _timer;
  int _seconds = 0;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    _seconds = _challenge.resendAfterSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds <= 1) {
        timer.cancel();
      }
      if (mounted) {
        setState(() => _seconds = (_seconds - 1).clamp(0, 3600));
      }
    });
  }

  void _showError(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is PasswordResetFailure
            ? error.message
            : 'Could not verify the code. Please try again.',
      ),
      backgroundColor: Colors.red,
    ),
  );
  Future<void> _verify() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final verified = await widget.service.verifyCode(_challenge, _code.text);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                ResetPasswordPage(verified: verified, service: widget.service),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resend() async {
    if (_seconds > 0 || _loading) return;
    setState(() => _loading = true);
    try {
      final challenge = await widget.service.requestCode(_challenge.email);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _code.clear();
        _startCooldown();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new code has been requested. Check your email.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    children: [
      const Text(
        'Verify Email',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 14),
      Text(
        'If ${_challenge.email} is registered, a four-digit code has been sent to it. Check your inbox or spam folder, then enter the code below.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
      ),
      const SizedBox(height: 10),
      const Text(
        'The code expires in 10 minutes.',
        style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
      ),
      const SizedBox(height: 18),
      Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey('reset-verification-code'),
          controller: _code,
          enabled: !_loading,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 12),
          decoration: const InputDecoration(
            labelText: 'Four-digit code',
            counterText: '',
          ),
          validator: (value) => RegExp(r'^\d{4}$').hasMatch(value ?? '')
              ? null
              : 'Enter all four digits.',
          onFieldSubmitted: (_) {
            if (!_loading) {
              _verify();
            }
          },
        ),
      ),
      const SizedBox(height: 18),
      ElevatedButton(
        onPressed: _loading ? null : _verify,
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
            : const Text('Verify code', style: TextStyle(fontSize: 16)),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _loading || _seconds > 0 ? null : _resend,
        child: Text(
          _seconds > 0 ? 'Resend code in ${_seconds}s' : 'Resend code',
        ),
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
