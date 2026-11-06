import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/medication_status_notification.dart';

typedef MedicationNotificationReader =
    Future<Map<String, dynamic>?> Function(String id);
typedef LatestMedicationActionReader =
    Future<Map<String, dynamic>?> Function(
      String patientId,
      String medicationId,
    );

/// Push data is a hint. Resolve authorization and the latest immutable action
/// from the server before exposing patient information on this device.
class MedicationNotificationAccess {
  MedicationNotificationAccess({
    String? Function()? currentUid,
    MedicationNotificationReader? readUser,
    MedicationNotificationReader? readMedication,
    LatestMedicationActionReader? readLatestAction,
  }) : _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _readUser = readUser ?? _user,
       _readMedication = readMedication ?? _medication,
       _readLatestAction = readLatestAction ?? _latestAction;

  final String? Function() _currentUid;
  final MedicationNotificationReader _readUser, _readMedication;
  final LatestMedicationActionReader _readLatestAction;

  static Future<Map<String, dynamic>?> _user(String id) async =>
      (await FirebaseFirestore.instance
              .collection('users')
              .doc(id)
              .get(const GetOptions(source: Source.server)))
          .data();

  static Future<Map<String, dynamic>?> _medication(String id) async =>
      (await FirebaseFirestore.instance
              .collection('medications')
              .doc(id)
              .get(const GetOptions(source: Source.server)))
          .data();

  static Future<Map<String, dynamic>?> _latestAction(
    String patientId,
    String medicationId,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('medication_actions')
        .where('patientId', isEqualTo: patientId)
        .where('medicationId', isEqualTo: int.parse(medicationId))
        .orderBy('timestamp', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(1)
        .get(const GetOptions(source: Source.server));
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.single;
    return {...doc.data(), 'id': doc.id};
  }

  Future<MedicationStatusNotification?> resolve(
    MedicationStatusNotification notification, {
    bool forAlert = true,
    DateTime? now,
  }) async {
    final uid = _currentUid();
    if (uid == null || uid != notification.recipientUid) return null;
    try {
      final profile = await _readUser(uid);
      if (!['caregiver', 'family'].contains(profile?['role'])) return null;
      final patient = await _readUser(notification.patientId);
      final medication = await _readMedication(notification.medicationId);
      if (_currentUid() != uid || patient == null || medication == null) {
        return null;
      }
      if (patient['role'] != 'patient' ||
          medication['patientId'] != notification.patientId) {
        return null;
      }
      final caregiverId = patient['caregiverId'];
      if (profile!['role'] == 'caregiver') {
        if (caregiverId != uid || medication['caregiverId'] != uid) return null;
      } else {
        final linked = profile['linkedPatientIds'];
        if (linked is! List || !linked.contains(notification.patientId)) {
          return null;
        }
      }
      if (forAlert) {
        if (medication['deletedAt'] != null) return null;
        final latest = await _readLatestAction(
          notification.patientId,
          notification.medicationId,
        );
        if (_currentUid() != uid ||
            latest == null ||
            latest['patientId'] != notification.patientId ||
            latest['medicationId'].toString() != notification.medicationId ||
            latest['timestamp'] is! int ||
            latest['action'] is! String ||
            !notification.shouldAlert(
              latestActionId: '${latest['id']}',
              latestAction: latest['action'] as String,
              latestActionTime: latest['timestamp'] as int,
              latestSnoozeUntil: latest['snoozeUntil'] as int?,
              now: now ?? DateTime.now(),
            )) {
          return null;
        }
      }
      if (_currentUid() != uid) return null;
      return notification.withNames(
        patientName: (patient['name'] as String?) ?? 'Patient',
        medicationName:
            (medication['name'] as String?) ?? notification.medicationName,
      );
    } catch (_) {
      // No cached authorization or outdated status fallback when offline.
      return null;
    }
  }
}
