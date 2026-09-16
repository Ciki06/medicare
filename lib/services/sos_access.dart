import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/sos_alert.dart';

/// Never trust a notification's cached role, recipient, or active status.
Future<SosAlert?> currentSosForRecipient(String alertId, String uid) async {
  if (alertId.isEmpty || FirebaseAuth.instance.currentUser?.uid != uid) {
    return null;
  }
  try {
    final db = FirebaseFirestore.instance;
    final profile = await db
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (!['caregiver', 'family'].contains(profile.data()?['role'])) return null;
    final snapshot = await db
        .collection('sos_alerts')
        .doc(alertId)
        .get(const GetOptions(source: Source.server));
    if (!snapshot.exists || FirebaseAuth.instance.currentUser?.uid != uid) {
      return null;
    }
    final alert = SosAlert.fromMap(snapshot.id, snapshot.data()!);
    return canReceiveSos(alert, uid, DateTime.now()) ? alert : null;
  } catch (_) {
    return null;
  }
}

bool canReceiveSos(SosAlert alert, String uid, DateTime now) =>
    alert.isActive &&
    alert.patientId != uid &&
    alert.alertUserIds.contains(uid) &&
    now.difference(alert.createdAt) >= Duration.zero &&
    now.difference(alert.createdAt) <= const Duration(minutes: 5);
