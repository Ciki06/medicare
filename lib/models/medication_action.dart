import '../services/cloud_record_fields.dart';

class MedicationAction {
  final String id;
  final String medicationId;
  final String medicationName;
  final String patientId;
  final String action;
  final int timestamp;
  final int? snoozedUntil;
  final String syncStatus;

  MedicationAction({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.patientId,
    required this.action,
    required this.timestamp,
    this.snoozedUntil,
    this.syncStatus = 'synced',
  });

  Map<String, dynamic> toMap() => {
    'medicationId': medicationId,
    'medicationName': medicationName,
    'patientId': patientId,
    'action': action,
    'timestamp': timestamp,
    if (snoozedUntil != null) 'snoozeUntil': snoozedUntil,
  };

  factory MedicationAction.fromMap(String id, Map<String, dynamic> map) =>
      MedicationAction(
        id: id,
        medicationId: CloudRecordFields.medicationKey(map),
        medicationName: map['medicationName'] as String,
        patientId: CloudRecordFields.patientUid(map),
        action: map['action'] as String,
        timestamp: map['timestamp'] as int,
        snoozedUntil: map['snoozeUntil'] as int?,
      );

  MedicationAction copyWith({String? id, String? syncStatus}) =>
      MedicationAction(
        id: id ?? this.id,
        medicationId: medicationId,
        medicationName: medicationName,
        patientId: patientId,
        action: action,
        timestamp: timestamp,
        snoozedUntil: snoozedUntil,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
