import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/local_caregiver_record.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import 'caregiver_sqlite_service.dart';

/// Isolates this opt-in profile copy from existing auth and Firestore operations.
class CaregiverLocalProfileService {
  CaregiverLocalProfileService({
    CaregiverSqliteService? database,
    String? Function()? currentUid,
    Future<UserModel?> Function(String uid)? loadProfile,
    Stream<String?>? uidChanges,
  }) : _database = database ?? CaregiverSqliteService.instance,
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _loadProfile = loadProfile ?? _readServerProfile,
       _uidChanges = uidChanges;

  final CaregiverSqliteService _database;
  final String? Function() _currentUid;
  final Future<UserModel?> Function(String uid) _loadProfile;
  final Stream<String?>? _uidChanges;

  Stream<String?> get uidChanges =>
      _uidChanges ??
      FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);

  static Future<UserModel?> _readServerProfile(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return doc.exists ? UserModel.fromMap(doc.data()!) : null;
  }

  void _checkSession(String uid) {
    if (uid.trim().isEmpty || _currentUid() != uid) {
      throw StateError('Sign in as this caregiver to access the local record.');
    }
  }

  Future<LocalCaregiverRecord?> load(String uid) async {
    _checkSession(uid);
    final record = await _database.getCaregiver(uid);
    _checkSession(uid);
    return record;
  }

  Future<LocalCaregiverRecord> saveCurrentProfile(String uid) async {
    _checkSession(uid);
    final profile = await _loadProfile(uid);
    _checkSession(uid);
    if (profile == null ||
        profile.uid != uid ||
        profile.role != UserRole.caregiver) {
      throw StateError('The current caregiver profile is unavailable.');
    }
    // Open before the final session check so an account change during SQLite
    // initialization cannot cause a stale profile to be written.
    await _database.database;
    _checkSession(uid);
    final record = await _database.saveCaregiver(
      profile,
      authenticatedUid: uid,
    );
    _checkSession(uid);
    return record;
  }
}
