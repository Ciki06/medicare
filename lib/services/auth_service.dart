import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../models/user_model.dart';
import '../models/user_role.dart';
import 'firestore_service.dart';
import 'cloud_identity_service.dart';
import 'local_profile_persistence_service.dart';
import 'notification_service.dart';
import 'patient_alarm_service.dart';
import 'reminder_service.dart';
import 'sos_launch_service.dart';
import 'medication_action_sync_service.dart';
import 'refill_request_sync_service.dart';

class AccountProfileSnapshot {
  const AccountProfileSnapshot(
    this.data, {
    this.isFromCache = false,
    this.hasPendingWrites = false,
  });
  final Map<String, dynamic>? data;
  final bool isFromCache;
  final bool hasPendingWrites;
}

class AuthService {
  static Completer<void>? _loginValidation;
  AuthService({
    LocalProfilePersistenceService? localProfiles,
    Stream<AccountProfileSnapshot> Function(String uid)? watchProfile,
  }) : _localProfiles = localProfiles ?? LocalProfilePersistenceService(),
       _watchProfile = watchProfile;

  final LocalProfilePersistenceService _localProfiles;
  final Stream<AccountProfileSnapshot> Function(String uid)? _watchProfile;
  static final _pendingRestores = <Object, UserModel>{};
  static final _lastRestored = <Object, String>{};
  static final _restoring = <Object>{};
  late final _ids = CloudIdentityService(database: _localProfiles.database);
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
    late StreamController<UserModel?> controller;
    StreamSubscription<auth.User?>? authentication;
    StreamSubscription<AccountProfileSnapshot>? profileSubscription;
    var generation = 0;
    var cancelled = false;
    Future<void> cacheWrites = Future.value();
    controller = StreamController<UserModel?>(
      onListen: () {
        authentication = _auth.authStateChanges().listen((firebaseUser) {
          final session = ++generation;
          final previous = profileSubscription;
          profileSubscription = null;
          unawaited(previous?.cancel());
          if (firebaseUser == null) {
            controller.add(null);
            return;
          }
          final uid = firebaseUser.uid;
          bool active() =>
              !cancelled &&
              generation == session &&
              _auth.currentUser?.uid == uid;
          unawaited(() async {
            // Hold navigation until login has checked the selected account role.
            await _loginValidation?.future;
            if (!active()) return;
            try {
              final initial = await _getUser(uid);
              if (!active()) return;
              controller.add(initial);
              var fingerprint = initial == null
                  ? ''
                  : jsonEncode(initial.toMap());
              profileSubscription =
                  (_watchProfile?.call(uid) ??
                          _firestore
                              .collection('users')
                              .doc(uid)
                              .snapshots(includeMetadataChanges: true)
                              .map(
                                (doc) => AccountProfileSnapshot(
                                  doc.data(),
                                  isFromCache: doc.metadata.isFromCache,
                                  hasPendingWrites:
                                      doc.metadata.hasPendingWrites,
                                ),
                              ))
                      .listen(
                        (snapshot) {
                          if (!active() ||
                              snapshot.isFromCache ||
                              snapshot.hasPendingWrites) {
                            return;
                          }
                          final data = snapshot.data;
                          if (data == null) {
                            fingerprint = '';
                            controller.add(null);
                            return;
                          }
                          late UserModel updated;
                          try {
                            updated = UserModel.fromMap({...data, 'uid': uid});
                          } catch (_) {
                            controller.add(null);
                            return;
                          }
                          final next = jsonEncode(updated.toMap());
                          if (next == fingerprint) return;
                          fingerprint = next;
                          controller.add(updated);
                          cacheWrites = cacheWrites.then((_) async {
                            if (!active()) return;
                            await _localProfiles.saveAuthenticatedProfile(uid, {
                              ...data,
                              'uid': uid,
                            });
                            if (active()) _scheduleRestore(updated);
                          });
                        },
                        onError: (Object error, StackTrace stack) {
                          if (active() &&
                              error is FirebaseException &&
                              const {
                                'permission-denied',
                                'unauthenticated',
                              }.contains(error.code)) {
                            controller.add(null);
                          }
                        },
                      );
            } catch (error, stack) {
              if (active()) controller.addError(error, stack);
            }
          }());
        }, onError: controller.addError);
      },
      onCancel: () async {
        cancelled = true;
        generation++;
        await authentication?.cancel();
        await profileSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<UserModel?> _getUser(String uid) async {
    // Prefer the server so up-to-date profile data (e.g. the shortId) is
    // reflected in the UI. The default source falls back to the offline cache
    // automatically when the server cannot be reached.
    final ref = _firestore.collection('users').doc(uid);
    final doc = await ref.get();
    if (_auth.currentUser?.uid != uid) return null;
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
      _scheduleRestore(profile, force: true);
    }
    return profile;
  }

  void _scheduleRestore(UserModel profile, {bool force = false}) {
    final key = _localProfiles.database;
    if (force) _lastRestored.remove(key);
    // Use the newest profile when the current local restore finishes.
    _pendingRestores[key] = profile;
    if (!_restoring.add(key)) return;
    unawaited(() async {
      try {
        while (_pendingRestores.containsKey(key)) {
          final latest = _pendingRestores.remove(key)!;
          final fingerprint = jsonEncode(latest.toMap());
          if (_auth.currentUser?.uid != latest.uid ||
              _lastRestored[key] == fingerprint) {
            continue;
          }
          try {
            await FirestoreService(
              localProfiles: _localProfiles,
              localDatabase: _localProfiles.database,
            ).restoreLocalRecords(latest);
            if (_auth.currentUser?.uid == latest.uid) {
              _lastRestored[key] = fingerprint;
            }
          } catch (_) {
            // A later confirmed profile or sign-in retries a failed hydration.
          }
        }
      } finally {
        _restoring.remove(key);
      }
    }());
  }

  /// Reconcile the profile's login address with Firebase Auth, the source of
  /// truth. Profile editing cannot submit a different sign-in email.
  Future<void> _syncEmailFromAuth(
    DocumentReference<Map<String, dynamic>> ref,
    Object? storedEmail,
  ) async {
    final currentEmail = _auth.currentUser?.email;
    if (currentEmail == null ||
        currentEmail == storedEmail ||
        ref.id != _auth.currentUser?.uid) {
      return;
    }
    try {
      await _ids.updateProfile(ref.id, {});
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
      final saved = await _ids.createProfile(user.toMap());
      await _localProfiles.saveAuthenticatedProfile(uid, saved);

      return UserModel.fromMap(saved);
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
    UserRole? expectedRole,
  }) async {
    final validation = Completer<void>();
    _loginValidation = validation;
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = userCredential.user!.uid;

      final user = await _getUser(uid);
      if (user == null) throw Exception('User data not found');
      if (expectedRole != null && user.role != expectedRole) {
        await _auth.signOut();
        throw auth.FirebaseAuthException(
          code: 'role-mismatch',
          message:
              'This account is registered as ${user.role.label}. Please select "${user.role.label}" to log in.',
        );
      }
      return user;
    } on auth.FirebaseAuthException catch (e) {
      throw auth.FirebaseAuthException(
        code: e.code,
        message: e.code == 'role-mismatch'
            ? e.message
            : _friendlyMessage(e.code),
      );
    } finally {
      validation.complete();
      if (identical(_loginValidation, validation)) _loginValidation = null;
    }
  }

  Future<void> signOut() async {
    // Stop account-bound work before Firebase broadcasts the signed-out state.
    await MedicationActionSyncService.instance.stop();
    await RefillRequestSyncService.instance.stop();
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
}
