import '../services/cloud_record_fields.dart';

class RefillRequest {
  final String id;
  final String medicationId;
  final String medicationName;
  final String patientId;
  final String patientName;
  final String caregiverId;
  final String caregiverName;

  /// Local SQLite pharmacist row assigned to this request, when known.
  final int? pharmacyId;
  final String? pharmacyUid;
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
    this.pharmacyId,
    this.pharmacyUid,
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
    if (pharmacyUid != null) 'pharmacyUid': pharmacyUid,
  };

  factory RefillRequest.fromMap(String id, Map<String, dynamic> map) =>
      RefillRequest(
        id: id,
        medicationId: CloudRecordFields.medicationKey(map),
        medicationName: map['medicationName'] as String,
        patientId: CloudRecordFields.patientUid(map),
        patientName: map['patientName'] as String,
        caregiverId: CloudRecordFields.caregiverUid(map),
        caregiverName: map['caregiverName'] as String,
        pharmacyUid: map['pharmacyUid'] as String?,
        status: (map['status'] as String?) ?? 'pending',
        quantityLeft: (map['quantityLeft'] as num?)?.toInt() ?? 0,
        quantityRequested: (map['quantityRequested'] as num?)?.toInt() ?? 0,
        requestedAt: (map['requestedAt'] as num).toInt(),
        updatedAt: (map['updatedAt'] as num?)?.toInt(),
      );

  RefillRequest copyWith({
    String? id,
    String? status,
    int? updatedAt,
    int? pharmacyId,
    String? pharmacyUid,
  }) => RefillRequest(
    id: id ?? this.id,
    medicationId: medicationId,
    medicationName: medicationName,
    patientId: patientId,
    patientName: patientName,
    caregiverId: caregiverId,
    caregiverName: caregiverName,
    pharmacyId: pharmacyId ?? this.pharmacyId,
    pharmacyUid: pharmacyUid ?? this.pharmacyUid,
    status: status ?? this.status,
    quantityLeft: quantityLeft,
    quantityRequested: quantityRequested,
    requestedAt: requestedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
