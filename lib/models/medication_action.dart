import '../services/cloud_record_fields.dart';

/// Stores medication actions such as taken, missed, or snoozed.
class MedicationAction {
  /// Checks and stores valid dosage information for new actions.
  static String? snapshotDosage(String? value) =>
      value == null || value.trim().isEmpty || value.length > 128
      ? null
      : value;

  /// Stores the medication and patient details.
  final String id;
  final String medicationId;
  final String medicationName;

  /// Stores the dosage recorded at the time of the action.
  final String? dosage;
  final String patientId;

  /// Stores the action type, time, and snooze details.
  final String action;
  final int timestamp;
  final int? snoozedUntil;

  /// Tracks whether the action has been synced.
  final String syncStatus;

  /// Creates a medication action with the required details.
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

  /// Converts medication action details into a map for cloud storage.
  Map<String, dynamic> toMap() => {
    'medicationId': medicationId,
    'medicationName': medicationName,
    if (dosage != null && dosage!.trim().isNotEmpty) 'dosage': dosage,
    'patientId': patientId,
    'action': action,
    'timestamp': timestamp,
    if (snoozedUntil != null) 'snoozeUntil': snoozedUntil,
  };

  /// Converts stored data into a MedicationAction object.
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

  /// Creates a copy of the action with an updated ID or sync status.
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
