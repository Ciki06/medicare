import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Caregiver-side account management that needs the trusted backend, such as
/// repointing the login email of an account the caregiver manages.
class ManagedAccountService {
  final _api = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// Changes the login email of [uid]. [caregiverPassword] is the signed-in
  /// caregiver's current password and is verified server-side.
  Future<void> updateEmail({
    required String uid,
    required String email,
    required String caregiverPassword,
  }) async {
    // The server verifies the password against the caller's ID token, which
    // Firebase only accepts for a few minutes after it was issued.
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    try {
      await _api.httpsCallable('updateManagedAccountEmail').call({
        'uid': uid,
        'email': email,
        'password': caregiverPassword,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Could not update the email address.');
    }
  }
}