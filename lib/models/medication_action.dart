class MedicationAction {
  final String id;
  final String medicationId;
  final String medicationName;
  final String patientId;
  final String action;
  final int timestamp;
  final int? snoozedUntil;

  MedicationAction({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.patientId,
    required this.action,
    required this.timestamp,
    this.snoozedUntil,
  });

  Map<String, dynamic> toMap() => {
    'medicationId': medicationId,
    'medicationName': medicationName,
    'patientId': patientId,
    'action': action,
    'timestamp': timestamp,
    if (snoozedUntil != null) 'snoozedUntil': snoozedUntil,
  };

  factory MedicationAction.fromMap(String id, Map<String, dynamic> map) =>
      MedicationAction(
        id: id,
        medicationId: map['medicationId'] as String,
        medicationName: map['medicationName'] as String,
        patientId: map['patientId'] as String,
        action: map['action'] as String,
        timestamp: map['timestamp'] as int,
        snoozedUntil: map['snoozedUntil'] as int?,
      );
}
