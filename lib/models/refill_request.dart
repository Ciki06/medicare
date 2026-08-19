class RefillRequest {
  final String id;
  final String medicationId;
  final String medicationName;
  final String patientId;
  final String patientName;
  final String caregiverId;
  final String caregiverName;
  final String status;
  final int quantityLeft;
  final int quantityRequested;
  final int requestedAt;
  final int? updatedAt;

  RefillRequest({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.patientId,
    required this.patientName,
    required this.caregiverId,
    required this.caregiverName,
    this.status = 'pending',
    this.quantityLeft = 0,
    this.quantityRequested = 0,
    required this.requestedAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'medicationId': medicationId,
    'medicationName': medicationName,
    'patientId': patientId,
    'patientName': patientName,
    'caregiverId': caregiverId,
    'caregiverName': caregiverName,
    'status': status,
    'quantityLeft': quantityLeft,
    'quantityRequested': quantityRequested,
    'requestedAt': requestedAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };

  factory RefillRequest.fromMap(String id, Map<String, dynamic> map) =>
      RefillRequest(
        id: id,
        medicationId: map['medicationId'] as String,
        medicationName: map['medicationName'] as String,
        patientId: map['patientId'] as String,
        patientName: map['patientName'] as String,
        caregiverId: map['caregiverId'] as String,
        caregiverName: map['caregiverName'] as String,
        status: (map['status'] as String?) ?? 'pending',
        quantityLeft: (map['quantityLeft'] as int?) ?? 0,
        quantityRequested: (map['quantityRequested'] as int?) ?? 0,
        requestedAt: map['requestedAt'] as int,
        updatedAt: map['updatedAt'] as int?,
      );
}
