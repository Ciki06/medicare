import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../models/user_model.dart';
import '../models/user_role.dart';
import 'firestore_service.dart';
import 'local_profile_persistence_service.dart';
import 'notification_service.dart';
import 'patient_alarm_service.dart';
import 'reminder_service.dart';
import 'sos_launch_service.dart';

class AuthService {
  AuthService({LocalProfilePersistenceService? localProfiles})
    : _localProfiles = localProfiles ?? LocalProfilePersistenceService();

  final LocalProfilePersistenceService _localProfiles;
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String _friendlyMessage(String code) {
    switch (code) {
      case 'CONFIGURATION_NOT_FOUND':
        return 'Email/Password sign-in is not enabled. Please contact support.';
      case 'EMAIL_EXISTS':
      case 'EMAIL_ALREADY_EXISTS':
        return 'An account with this email already exists.';
      case 'OPERATION_NOT_ALLOWED':
        return 'Email/Password sign-in is not enabled.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Please try again later.';
      case 'EMAIL_NOT_FOUND':
        return 'No account found with this email.';
      case 'INVALID_PASSWORD':
        return 'Invalid password.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'INVALID_EMAIL':
        return 'Invalid email address.';
      case 'WEAK_PASSWORD':
        return 'Password should be at least 6 characters.';
      default:
        return code;
    }
  }

  Stream<UserModel?> get user {
    return _auth.authStateChanges().asyncMap((firebaseUser) {
      if (firebaseUser == null) return null;
      return _getUser(firebaseUser.uid);
    });
  }

  Future<UserModel?> _getUser(String uid) async {
    // Prefer the server so up-to-date profile data (e.g. the shortId) is
    // reflected in the UI. The default source falls back to the offline cache
    // automatically when the server cannot be reached.
    final ref = _firestore.collection('users').doc(uid);
    final doc = await ref.get();
    if (!doc.exists) return null;
    await _syncEmailFromAuth(ref, doc.data()!['email']);
    // The Firestore document path is the authoritative Firebase UID. Keep a
    // stale/missing uid field in an older profile from querying schedules for
    // the wrong patient ID.
    final profileData = {...doc.data()!, 'uid': uid};
    final profile = UserModel.fromMap(profileData);
    // AuthGate uses this path after direct Firebase sign-in and session restore.
    // Pending/offline profile changes are not confirmed Firebase account data.
    if (!doc.metadata.isFromCache && !doc.metadata.hasPendingWrites) {
      await _localProfiles.saveAuthenticatedProfile(uid, {
        ...profileData,
        if (_auth.currentUser?.uid == uid && _auth.currentUser?.email != null)
          'email': _auth.currentUser!.email,
      });
    }
    return profile;
  }

  /// Firebase Auth is the source of truth for the login address: it only
  /// applies an email change once the caregiver confirms the new address, so
  /// the profile document is reconciled to it on the next auth state change.
  Future<void> _syncEmailFromAuth(
    DocumentReference<Map<String, dynamic>> ref,
    Object? storedEmail,
  ) async {
    final currentEmail = _auth.currentUser?.email;
    if (currentEmail == null || currentEmail == storedEmail) return;
    try {
      await ref.update({'email': currentEmail});
    } catch (_) {
      // Only the signed-in user may write their own document; a failed sync is
      // retried on the next auth state change.
    }
  }

  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? caregiverId,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = userCredential.user!.uid;

      final user = UserModel(
        uid: uid,
        name: name,
        email: email,
        role: role,
        createdAt: DateTime.now(),
        caregiverId: caregiverId,
        profilePicUrl: null,
        shortId: UserModel.generateId(role),
      );
      await _firestore.collection('users').doc(uid).set(user.toMap());
      await _localProfiles.saveAuthenticatedProfile(uid, user.toMap());

      return user;
    } on auth.FirebaseAuthException catch (e) {
      throw auth.FirebaseAuthException(
        code: e.code,
        message: _friendlyMessage(e.code),
      );
    }
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = userCredential.user!.uid;

      final user = await _getUser(uid);
      if (user == null) throw Exception('User data not found');
      return user;
    } on auth.FirebaseAuthException catch (e) {
      throw auth.FirebaseAuthException(
        code: e.code,
        message: _friendlyMessage(e.code),
      );
    }
  }

  Future<void> signOut() async {
    NotificationService.instance.clearSessionCallbacks();
    SosLaunchService.instance.consumePendingSosRequest();
    ReminderService().reset();
    try {
      await NotificationService.instance.cancelAll();
    } catch (_) {}
    try {
      await PatientAlarmService.stop();
    } catch (_) {}
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await FirestoreService().removeFcmToken(uid, token);
        }
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {
        // Signing out must still succeed if token cleanup is unavailable.
      }
    }
    await _auth.signOut();
  }

  /// Verifies the currently signed-in user's current password, then updates it
  /// to [newPassword]. Throws on an invalid current password or a failed update.
  Future<void> reauthenticateAndUpdatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final credential = auth.EmailAuthProvider.credential(
      email: user.email ?? '',
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  /// Verifies the currently signed-in user's current password and asks Firebase
  /// to email a confirmation link to [newEmail]. The address only changes once
  /// that link is opened, so a typo cannot lock the caregiver out of the
  /// account. Throws on an invalid current password or a failed update.
  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final credential = auth.EmailAuthProvider.credential(
      email: user.email ?? '',
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    try {
      await user.verifyBeforeUpdateEmail(newEmail);
    } on auth.FirebaseAuthException catch (e) {
      throw auth.FirebaseAuthException(
        code: e.code,
        message: _friendlyMessage(e.code),
      );
    }
  }
}
