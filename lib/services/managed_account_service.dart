import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Caregiver-side account management that needs the trusted backend, such as
/// repointing the login email of an account the caregiver manages.
class ManagedAccountService {
  final _api = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// Changes the login email of [uid]. [caregiverPassword] is the signed-in
  /// caregiver's current password, verified by Firebase reauthentication.
  Future<void> updateEmail({
    required String uid,
    required String email,
    required String caregiverPassword,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      throw StateError('Sign in before managing an account.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(
        email: user.email!,
        password: caregiverPassword,
      ),
    );
    await user.getIdToken(true);
    try {
      await _api.httpsCallable('updateManagedAccountEmail').call({
        'uid': uid,
        'email': email,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Could not update the email address.');
    }
  }
}
