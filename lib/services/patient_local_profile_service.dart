import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/local_patient_record.dart';
import 'caregiver_sqlite_service.dart';

/// An explicit local profile copy, independent of login and business writes.
class PatientLocalProfileService {
  PatientLocalProfileService({
    CaregiverSqliteService? database,
    String? Function()? currentUid,
    Future<Map<String, dynamic>?> Function(String uid)? loadProfile,
    Stream<String?>? uidChanges,
  }) : _database = database ?? CaregiverSqliteService.instance,
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _loadProfile = loadProfile ?? _readServerProfile,
       _uidChanges = uidChanges;

  final CaregiverSqliteService _database;
  final String? Function() _currentUid;
  final Future<Map<String, dynamic>?> Function(String uid) _loadProfile;
  final Stream<String?>? _uidChanges;

  Stream<String?> get uidChanges =>
      _uidChanges ??
      FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);

  static Future<Map<String, dynamic>?> _readServerProfile(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return doc.data();
  }

  void _checkSession(String uid) {
    if (uid.trim().isEmpty || _currentUid() != uid) {
      throw StateError('Sign in as this patient to access the local record.');
    }
  }

  Future<LocalPatientRecord?> load(String uid) async {
    _checkSession(uid);
    final record = await _database.getPatient(uid);
    _checkSession(uid);
    return record;
  }

  Future<LocalPatientRecord> saveCurrentProfile(String uid) async {
    _checkSession(uid);
    final profile = await _loadProfile(uid);
    _checkSession(uid);
    if (profile == null ||
        profile['role'] != 'patient' ||
        (profile['uid'] != null && profile['uid'] != uid)) {
      throw StateError('The current patient profile is unavailable.');
    }
    await _database.database;
    _checkSession(uid);
    final record = await _database.savePatient(
      uid,
      profile,
      authenticatedUid: uid,
    );
    _checkSession(uid);
    return record;
  }
}
