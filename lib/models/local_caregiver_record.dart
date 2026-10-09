/// A small local profile snapshot. No authentication or business data is stored.
class LocalCaregiverRecord {
  const LocalCaregiverRecord({
    required this.caregiverId,
    required this.firebaseUid,
    required this.name,
    required this.email,
    this.phone,
    this.profilePicUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final int caregiverId;
  final String firebaseUid;
  final String name;
  final String email;
  final String? phone;

  /// Image reference only; URL query parameters (including tokens) are omitted.
  final String? profilePicUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory LocalCaregiverRecord.fromMap(Map<String, Object?> map) =>
      LocalCaregiverRecord(
        caregiverId: map['caregiver_id'] as int,
        firebaseUid: map['firebase_uid'] as String,
        name: map['name'] as String,
        email: map['email'] as String,
        phone: map['phone'] as String?,
        profilePicUrl: map['profile_pic_url'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
