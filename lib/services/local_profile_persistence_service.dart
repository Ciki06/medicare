import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'caregiver_sqlite_service.dart';

/// Copies confirmed account profiles after Firebase succeeds. Local failures
/// never invalidate an account or prevent Firebase login/registration.
/// This is not a background sync or a business-data write path.
class LocalProfilePersistenceService {
  LocalProfilePersistenceService({
    CaregiverSqliteService? database,
    String? Function()? currentUid,
    Future<Map<String, dynamic>?> Function(String uid)? loadCaregiver,
  }) : _database = database ?? CaregiverSqliteService.instance,
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _loadCaregiver = loadCaregiver ?? _readCaregiver;

  final CaregiverSqliteService _database;
  final String? Function() _currentUid;
  final Future<Map<String, dynamic>?> Function(String uid) _loadCaregiver;

  static Future<Map<String, dynamic>?> _readCaregiver(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return doc.data();
  }

  void _checkSession(String uid) {
    if (uid.trim().isEmpty || _currentUid() != uid) {
      throw StateError('The authenticated account changed.');
    }
  }

  Future<bool> saveAuthenticatedProfile(
    String uid,
    Map<String, dynamic> profile,
  ) async {
    try {
      _checkSession(uid);
      if (profile['uid'] != uid) throw StateError('Profile UID mismatch.');
      if (![
        'caregiver',
        'patient',
        'family',
        'pharmacist',
      ].contains(profile['role'])) {
        return false;
      }
      await _database.database;
      _checkSession(uid);
      if (profile['role'] == 'caregiver') {
        await _database.saveCaregiver(
          UserModel.fromMap(profile),
          authenticatedUid: uid,
        );
      } else if (profile['role'] == 'patient') {
        await _database.savePatient(uid, profile, authenticatedUid: uid);
      } else if (profile['role'] == 'family') {
        await _database.saveFamily(uid, profile);
      } else {
        await _database.savePharmacist(uid, profile);
      }
      _checkSession(uid);
      return true;
    } catch (_) {
      // Never log the profile, UID, credential, or database exception.
      debugPrint(
        'Automatic local profile save was unavailable. It will retry at the next sign-in.',
      );
      return false;
    }
  }

  /// The account API creates a patient without replacing the caregiver's
  /// Firebase session. Verify that caregiver before saving the new patient;
  /// never pretend the patient UID is the authenticated UID.
  Future<bool> saveCreatedPatient(
    Map<String, dynamic> profile, {
    required String caregiverUid,
  }) async {
    try {
      _checkSession(caregiverUid);
      if (profile['role'] != 'patient' ||
          profile['caregiverId'] != caregiverUid ||
          profile['uid'] is! String ||
          (profile['uid'] as String).trim().isEmpty) {
        throw StateError('Invalid registered patient profile.');
      }
      final data = await _loadCaregiver(caregiverUid);
      _checkSession(caregiverUid);
      if (data == null ||
          data['uid'] != caregiverUid ||
          data['role'] != 'caregiver') {
        throw StateError('An authenticated caregiver is required.');
      }
      final caregiver = UserModel.fromMap(data);
      await _database.database;
      _checkSession(caregiverUid);
      // Save the authenticated caregiver first to resolve the local foreign key.
      await _database.saveCaregiver(caregiver, authenticatedUid: caregiverUid);
      _checkSession(caregiverUid);
      await _database.savePatientCreatedByCaregiver(
        profile['uid'] as String,
        profile,
        caregiver: caregiver,
      );
      _checkSession(caregiverUid);
      return true;
    } catch (_) {
      debugPrint(
        'Automatic local patient save was unavailable. The Firebase account remains available and can be saved at sign-in.',
      );
      return false;
    }
  }

  /// Family accounts are created by an authenticated caregiver using the
  /// Firebase account API, which does not replace that caregiver's session.
  Future<bool> saveCreatedFamily(
    Map<String, dynamic> profile, {
    required String caregiverUid,
  }) async {
    try {
      _checkSession(caregiverUid);
      if (profile['role'] != 'family' ||
          profile['uid'] is! String ||
          (profile['uid'] as String).trim().isEmpty) {
        throw StateError('Invalid registered family profile.');
      }
      final caregiver = await _loadCaregiver(caregiverUid);
      _checkSession(caregiverUid);
      if (caregiver == null ||
          caregiver['uid'] != caregiverUid ||
          caregiver['role'] != 'caregiver') {
        throw StateError('An authenticated caregiver is required.');
      }
      await _database.database;
      _checkSession(caregiverUid);
      await _database.saveFamily(profile['uid'] as String, profile);
      _checkSession(caregiverUid);
      return true;
    } catch (_) {
      debugPrint(
        'Automatic local family save was unavailable. Firebase account remains available and can be saved at sign-in.',
      );
      return false;
    }
  }

  /// Pharmacist accounts created through the caregiver account screen use the
  /// Firebase account API without replacing the caregiver's authenticated session.
  Future<bool> saveCreatedPharmacist(
    Map<String, dynamic> profile, {
    required String caregiverUid,
  }) async {
    try {
      _checkSession(caregiverUid);
      if (profile['role'] != 'pharmacist' ||
          profile['caregiverId'] != caregiverUid ||
          profile['uid'] is! String ||
          (profile['uid'] as String).trim().isEmpty) {
        throw StateError('Invalid registered pharmacist profile.');
      }
      final caregiver = await _loadCaregiver(caregiverUid);
      _checkSession(caregiverUid);
      if (caregiver == null ||
          caregiver['uid'] != caregiverUid ||
          caregiver['role'] != 'caregiver') {
        throw StateError('An authenticated caregiver is required.');
      }
      await _database.database;
      _checkSession(caregiverUid);
      await _database.savePharmacist(profile['uid'] as String, profile);
      _checkSession(caregiverUid);
      return true;
    } catch (_) {
      debugPrint(
        'Automatic local pharmacist save was unavailable. Firebase account remains available and can be saved at sign-in.',
      );
      return false;
    }
  }
}
