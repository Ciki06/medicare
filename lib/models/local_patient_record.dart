/// The patient's local profile and current medical conditions, without auth data.
class LocalPatientRecord {
  const LocalPatientRecord({
    required this.patientId,
    required this.uid,
    this.name,
    this.icNumber,
    this.gender,
    this.dateOfBirth,
    this.phone,
    this.email,
    this.address,
    this.caregiverId,
    this.medicalHistory = const [],
  });

  final int patientId;
  final String uid;
  final String? name;
  final String? icNumber;
  final String? gender;
  final String? dateOfBirth;
  final String? phone;
  final String? email;
  final String? address;
  final int? caregiverId;
  final List<LocalPatientMedicalHistory> medicalHistory;

  factory LocalPatientRecord.fromMap(
    Map<String, Object?> map,
    List<Map<String, Object?>> history,
  ) => LocalPatientRecord(
    patientId: map['patient_id'] as int,
    uid: map['uid'] as String,
    name: map['name'] as String?,
    icNumber: map['ic_number'] as String?,
    gender: map['gender'] as String?,
    dateOfBirth: map['date_of_birth'] as String?,
    phone: map['phone'] as String?,
    email: map['email'] as String?,
    address: map['address'] as String?,
    caregiverId: map['caregiver_id'] as int?,
    medicalHistory: List.unmodifiable(
      history.map(LocalPatientMedicalHistory.fromMap),
    ),
  );

  int? get age => ageAt(DateTime.now());

  /// Firestore uses DD/MM/YYYY. Also accepts an ISO date, validating calendar
  /// components so invalid/future dates never produce a misleading age.
  int? ageAt(DateTime today) {
    final text = dateOfBirth?.trim();
    if (text == null) return null;
    final local = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(text);
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (local == null && iso == null) return null;
    final year = int.parse(local?.group(3) ?? iso!.group(1)!);
    final month = int.parse(local?.group(2) ?? iso!.group(2)!);
    final day = int.parse(local?.group(1) ?? iso!.group(3)!);
    final birthday = DateTime(year, month, day);
    if (year < 1 ||
        birthday.year != year ||
        birthday.month != month ||
        birthday.day != day ||
        birthday.isAfter(DateTime(today.year, today.month, today.day))) {
      return null;
    }
    var years = today.year - year;
    if (today.month < month || (today.month == month && today.day < day)) {
      years--;
    }
    return years;
  }
}

class LocalPatientMedicalHistory {
  const LocalPatientMedicalHistory({
    required this.historyId,
    required this.patientId,
    required this.medicalHistory,
    this.createdAt,
  });

  final int historyId;
  final int patientId;
  final String medicalHistory;

  /// When this condition was first copied locally, not its diagnosis date.
  final DateTime? createdAt;

  factory LocalPatientMedicalHistory.fromMap(Map<String, Object?> map) =>
      LocalPatientMedicalHistory(
        historyId: map['history_id'] as int,
        patientId: map['patient_id'] as int,
        medicalHistory: map['medical_history'] as String? ?? '',
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
      );
}
