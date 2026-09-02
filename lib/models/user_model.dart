import 'dart:math';

import 'malaysian_ic.dart';
import 'user_role.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final DateTime createdAt;
  final String? caregiverId;
  final String? phone;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String? registeredId;
  final String? icNumber;
  final List<String> medicalHistory;
  final String? medicalNotes;
  final String? profilePicUrl;
  final String? shortId;
  final List<String> linkedPatientIds;
  final List<String> linkedPatientEmails;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.createdAt,
    this.caregiverId,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.registeredId,
    this.icNumber,
    this.medicalHistory = const [],
    this.medicalNotes,
    this.profilePicUrl,
    this.shortId,
    this.linkedPatientIds = const [],
    this.linkedPatientEmails = const [],
  });

  int? get age => icNumber == null ? null : MalaysianIc.age(icNumber!);

  String get displayId =>
      shortId ?? _deriveShortId();

  static String generateId(UserRole role) {
    final rand = Random();
    final num = rand.nextInt(9000) + 1000;
    return switch (role) {
      UserRole.caregiver => 'CG-$num',
      UserRole.patient => 'PT-$num',
      UserRole.family => 'FM-$num',
      UserRole.pharmacist => 'PH-$num',
    };
  }

  String _deriveShortId() {
    final suffix = uid.length > 8
        ? uid.substring(uid.length - 8).toUpperCase()
        : uid.toUpperCase();
    return switch (role) {
      UserRole.caregiver => 'CG-$suffix',
      UserRole.patient => 'PT-$suffix',
      UserRole.family => 'FM-$suffix',
      UserRole.pharmacist => 'PH-$suffix',
    };
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'email': email,
    'role': role.name,
    'createdAt': createdAt.toIso8601String(),
    if (caregiverId != null) 'caregiverId': caregiverId,
    if (phone != null) 'phone': phone,
    if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
    if (gender != null) 'gender': gender,
    if (address != null) 'address': address,
    if (registeredId != null) 'registeredId': registeredId,
    if (icNumber != null) 'icNumber': icNumber,
    if (medicalHistory.isNotEmpty) 'medicalHistory': medicalHistory,
    if (medicalNotes != null && medicalNotes!.isNotEmpty) 'medicalNotes': medicalNotes,
    if (profilePicUrl != null) 'profilePicUrl': profilePicUrl,
    if (shortId != null) 'shortId': shortId,
    if (linkedPatientIds.isNotEmpty) 'linkedPatientIds': linkedPatientIds,
    if (linkedPatientEmails.isNotEmpty)
      'linkedPatientEmails': linkedPatientEmails,
  };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
    uid: map['uid'] as String,
    name: map['name'] as String,
    email: map['email'] as String,
    role: UserRole.values.firstWhere((r) => r.name == map['role']),
    createdAt: DateTime.parse(map['createdAt'] as String),
    caregiverId: map['caregiverId'] as String?,
    phone: map['phone'] as String?,
    dateOfBirth: map['dateOfBirth'] as String?,
    gender: map['gender'] as String?,
    address: map['address'] as String?,
    registeredId: map['registeredId'] as String?,
    icNumber: map['icNumber'] as String?,
    medicalHistory:
        (map['medicalHistory'] as List?)?.cast<String>() ?? const [],
    medicalNotes: map['medicalNotes'] as String?,
    profilePicUrl: map['profilePicUrl'] as String?,
    shortId: map['shortId'] as String?,
    linkedPatientIds:
        (map['linkedPatientIds'] as List?)?.cast<String>() ??
            (map['linkedPatientId'] == null
                ? const <String>[]
                : <String>[map['linkedPatientId'] as String]),
    linkedPatientEmails:
        (map['linkedPatientEmails'] as List?)?.cast<String>() ??
            (map['linkedPatientEmail'] == null
                ? const <String>[]
                : <String>[map['linkedPatientEmail'] as String]),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel && runtimeType == other.runtimeType && uid == other.uid;

  @override
  int get hashCode => uid.hashCode;
}
