import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PasswordResetChallenge {
  const PasswordResetChallenge({
    required this.email,
    required this.id,
    this.resendAfterSeconds = 60,
  });
  final String email;
  final String id;
  final int resendAfterSeconds;
}

class VerifiedPasswordReset {
  const VerifiedPasswordReset({required this.email, required this.resetCode});
  final String email;
  // Firebase's reset credential stays in memory after OTP verification.
  final String resetCode;
}

class PasswordResetFailure implements Exception {
  const PasswordResetFailure(this.message);
  final String message;
}

abstract interface class PasswordResetGateway {
  Future<PasswordResetChallenge> requestCode(String email);
  Future<VerifiedPasswordReset> verifyCode(
    PasswordResetChallenge challenge,
    String code,
  );
  Future<void> resetPassword(VerifiedPasswordReset verified, String password);
}

class FirebasePasswordResetService implements PasswordResetGateway {
  FirebasePasswordResetService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  }) : _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
       _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
          )
          .call(data);
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw PasswordResetFailure(switch (error.code) {
        'unavailable' || 'deadline-exceeded' =>
          'Could not connect. Check your internet connection and try again.',
        'not-found' || 'unimplemented' =>
          'Password reset is not available yet. Please try again later.',
        _ =>
          error.message ??
              'Could not complete password reset. Please try again.',
      });
    }
  }

  @override
  Future<PasswordResetChallenge> requestCode(String email) async {
    final normalized = email.trim().toLowerCase();
    final data = await _call('requestPasswordResetCode', {'email': normalized});
    return PasswordResetChallenge(
      email: normalized,
      id: data['challengeId'] as String,
      resendAfterSeconds: (data['resendAfterSeconds'] as num?)?.toInt() ?? 60,
    );
  }

  @override
  Future<VerifiedPasswordReset> verifyCode(
    PasswordResetChallenge challenge,
    String code,
  ) async {
    final result = await _call('verifyPasswordResetCode', {
      'email': challenge.email,
      'challengeId': challenge.id,
      'code': code,
    });
    return VerifiedPasswordReset(
      email: result['email'] as String,
      resetCode: result['resetCode'] as String,
    );
  }

  @override
  Future<void> resetPassword(
    VerifiedPasswordReset verified,
    String password,
  ) async {
    try {
      await _auth.confirmPasswordReset(
        code: verified.resetCode,
        newPassword: password,
      );
    } on FirebaseAuthException catch (error) {
      throw PasswordResetFailure(switch (error.code) {
        'weak-password' =>
          'Choose a stronger password with at least 6 characters.',
        'expired-action-code' || 'invalid-action-code' =>
          'Your reset session has expired. Please request a new code.',
        'network-request-failed' =>
          'Check your internet connection and try again.',
        _ =>
          'Could not reset the password. Please request a new code and try again.',
      });
    }
  }
}
