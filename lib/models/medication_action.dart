import '../services/cloud_record_fields.dart';

class MedicationAction {
  /// Only new event capture uses this bound. Existing outbox payloads must not
  /// be rewritten, and long legacy prescription text must not block an action.
  static String? snapshotDosage(String? value) =>
      value == null || value.trim().isEmpty || value.length > 128
      ? null
      : value;

  final String id;
  final String medicationId;
  final String medicationName;

  /// Prescription text captured when this event was recorded. Older events
  /// intentionally remain unset rather than borrowing a later schedule's dose.
  final String? dosage;
  final String patientId;
  final String action;
  final int timestamp;
  final int? snoozedUntil;
  // Upload state is local bookkeeping, not part of the cloud action payload.
  final String syncStatus;

  MedicationAction({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    this.dosage,
    required this.patientId,
    required this.action,
    required this.timestamp,
    this.snoozedUntil,
    this.syncStatus = 'synced',
  });

  Map<String, dynamic> toMap() => {
    'medicationId': medicationId,
    'medicationName': medicationName,
    if (dosage != null && dosage!.trim().isNotEmpty) 'dosage': dosage,
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
        dosage: map['dosage'] as String?,
        patientId: CloudRecordFields.patientUid(map),
        action: map['action'] as String,
        timestamp: map['timestamp'] as int,
        snoozedUntil: map['snoozeUntil'] as int?,
        syncStatus: (map['syncStatus'] as String?) ?? 'synced',
      );

  MedicationAction copyWith({String? id, String? syncStatus}) =>
      MedicationAction(
        id: id ?? this.id,
        medicationId: medicationId,
        medicationName: medicationName,
        dosage: dosage,
        patientId: patientId,
        action: action,
        timestamp: timestamp,
        snoozedUntil: snoozedUntil,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
