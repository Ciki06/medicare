class SosAlert {
  final String id;
  final String patientId;
  final String patientName;
  final String caregiverId;
  final List<String> alertUserIds;
  final String status;
  final DateTime createdAt;

  SosAlert({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.caregiverId,
    required this.alertUserIds,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'patientId': patientId,
        'patientName': patientName,
        'caregiverId': caregiverId,
        'alertUserIds': alertUserIds,
        'status': status,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory SosAlert.fromMap(String id, Map<String, dynamic> map) => SosAlert(
        id: id,
        patientId: map['patientId'] as String,
        patientName: map['patientName'] as String,
        caregiverId: map['caregiverId'] as String,
        alertUserIds:
            (map['alertUserIds'] as List?)?.cast<String>() ?? const [],
        status: map['status'] as String? ?? 'active',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );

  bool get isActive => status == 'active';
}