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
    'id': id,
    'medicationId': medicationId,
    'medicationName': medicationName,
    'patientId': patientId,
    'action': action,
    'timestamp': timestamp,
    if (snoozedUntil != null) 'snoozeUntil': snoozedUntil,
    'syncStatus': syncStatus,
  };

  factory MedicationAction.fromMap(String id, Map<String, dynamic> map) =>
      MedicationAction(
        id: id,
        medicationId: map['medicationId'] as String,
        medicationName: map['medicationName'] as String,
        patientId: map['patientId'] as String,
        action: map['action'] as String,
        timestamp: map['timestamp'] as int,
        snoozedUntil:
            (map['snoozedUntil'] ?? map['snoozeUntil']) as int?,
        syncStatus: map['syncStatus'] as String? ?? 'synced',
      );

  MedicationAction copyWith({String? syncStatus}) => MedicationAction(
    id: id,
    medicationId: medicationId,
    medicationName: medicationName,
    patientId: patientId,
    action: action,
    timestamp: timestamp,
    snoozedUntil: snoozedUntil,
    syncStatus: syncStatus ?? this.syncStatus,
  );
}
