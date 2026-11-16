/// Stores emergency SOS alerts created by patients.
class SosAlert {
  /// Stores the patient, caregiver, and alert information.
  final String id;
  final String patientId;
  final String patientName;
  final String caregiverId;
  final List<String> alertUserIds;
  final String status;
  final DateTime createdAt;

  /// Creates an SOS alert with the required details.
  SosAlert({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.caregiverId,
    required this.alertUserIds,
    required this.status,
    required this.createdAt,
  });

  /// Converts SOS alert details into a map for cloud storage.
  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'patientName': patientName,
    'caregiverId': caregiverId,
    'alertUserIds': alertUserIds,
    'status': status,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  /// Converts stored data into an SosAlert object.
  factory SosAlert.fromMap(String id, Map<String, dynamic> map) => SosAlert(
    id: id,
    patientId: map['patientId'] as String,
    patientName: map['patientName'] as String,
    caregiverId: map['caregiverId'] as String,
    alertUserIds: (map['alertUserIds'] as List?)?.cast<String>() ?? const [],
    status: map['status'] as String? ?? 'active',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    ),
  );

  /// Checks whether the SOS alert is still active.
  bool get isActive => status == 'active';
}
