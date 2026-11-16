import '../services/cloud_record_fields.dart';

/// Stores medication refill requests and their status.
class RefillRequest {
  /// Stores the medication, patient, and caregiver details.
  final String id;
  final String medicationId;
  final String medicationName;
  final String patientId;
  final String patientName;
  final String caregiverId;
  final String caregiverName;

  /// Stores the pharmacy information assigned to the request.
  final int? pharmacyId;
  final String? pharmacyUid;

  /// Tracks the refill status, stock quantity, and request dates.
  final String status;
  final int quantityLeft;
  final int quantityRequested;
  final int requestedAt;
  final int? updatedAt;

  /// Creates a refill request with the required details.
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
    String status = 'pending',
    this.quantityLeft = 0,
    this.quantityRequested = 0,
    required this.requestedAt,
    this.updatedAt,
  }) : status = status == 'processing' ? 'pending' : status;

  /// Converts refill request details into a map for cloud storage.
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

  /// Converts stored data into a RefillRequest object.
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

  /// Creates a copy of the refill request with updated details.
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
