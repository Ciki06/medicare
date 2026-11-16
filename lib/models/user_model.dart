import 'dart:math';

import 'malaysian_ic.dart';
import 'user_role.dart';

/// Stores user profile details, account roles, and linked patient information.
class UserModel {
  /// Stores the user's account and personal information.
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
  final String? relationship;

  /// Stores family relationships and additional profile information.
  final Map<String, String> patientRelationships;
  final String? registeredId;
  final String? icNumber;
  final List<String> medicalHistory;
  final String? medicalNotes;
  final String? profilePicUrl;
  final String? shortId;

  /// Stores the IDs and emails of linked patients.
  final List<String> linkedPatientIds;
  final List<String> linkedPatientEmails;

  /// Creates a user profile with the required and optional details.
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
    this.relationship,
    this.patientRelationships = const {},
    this.registeredId,
    this.icNumber,
    this.medicalHistory = const [],
    this.medicalNotes,
    this.profilePicUrl,
    this.shortId,
    this.linkedPatientIds = const [],
    this.linkedPatientEmails = const [],
  });

  /// Calculates the user's age from the Malaysian IC number.
  int? get age => icNumber == null ? null : MalaysianIc.age(icNumber!);
  // Converts the date of birth into a readable format.
  String? get displayDateOfBirth {
    if (dateOfBirth == null) return null;
    final date = DateTime.tryParse(dateOfBirth!);
    if (date == null) return dateOfBirth;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Returns the user's short ID for display.
  String get displayId => shortId ?? _deriveShortId();

  /// Generates a random four-digit ID based on the user role.
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

  /// Creates a short ID using the Firebase UID when no short ID is available.
  String _deriveShortId() {
    final suffix = uid.length > 4
        ? uid.substring(uid.length - 4).toUpperCase()
        : uid.toUpperCase();
    return switch (role) {
      UserRole.caregiver => 'CG-$suffix',
      UserRole.patient => 'PT-$suffix',
      UserRole.family => 'FM-$suffix',
      UserRole.pharmacist => 'PH-$suffix',
    };
  }

  /// Converts user profile details into a map for cloud storage.
  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'email': email,
    'role': role.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (caregiverId != null) 'caregiverId': caregiverId,
    if (phone != null) 'phone': phone,
    if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
    if (gender != null) 'gender': gender,
    if (address != null) 'address': address,
    if (relationship != null) 'relationship': relationship,
    'patientRelationships': patientRelationships,
    if (registeredId != null) 'registeredId': registeredId,
    if (icNumber != null) 'icNumber': icNumber,
    if (medicalHistory.isNotEmpty) 'medicalHistory': medicalHistory,
    if (medicalNotes != null && medicalNotes!.isNotEmpty)
      'medicalNotes': medicalNotes,
    if (profilePicUrl != null) 'profilePicUrl': profilePicUrl,
    if (shortId != null) 'shortId': shortId,
    if (linkedPatientIds.isNotEmpty) 'linkedPatientIds': linkedPatientIds,
    if (linkedPatientEmails.isNotEmpty)
      'linkedPatientEmails': linkedPatientEmails,
  };

  /// Converts stored data into a UserModel object.
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
    relationship: map['relationship'] as String?,
    patientRelationships: Map<String, String>.from(
      map['patientRelationships'] as Map? ?? const {},
    ),
    registeredId: map['registeredId'] as String?,
    icNumber: map['icNumber'] as String?,
    medicalHistory:
        (map['medicalHistory'] as List?)?.cast<String>() ?? const [],
    medicalNotes: map['medicalNotes'] as String?,
    profilePicUrl: map['profilePicUrl'] as String?,
    shortId: map['shortId'] as String?,
    linkedPatientIds:
        (map['linkedPatientIds'] as List?)?.cast<String>() ?? const [],
    linkedPatientEmails:
        (map['linkedPatientEmails'] as List?)?.cast<String>() ?? const [],
  );

  /// Gets the relationship between the user and a selected patient.
  String relationshipForPatient(String uid) =>
      patientRelationships[uid] ?? relationship ?? '';

  /// Creates a readable summary of all linked patient relationships.
  String get relationshipSummary => linkedPatientIds
      .asMap()
      .entries
      .map((entry) {
        final label = entry.key < linkedPatientEmails.length
            ? linkedPatientEmails[entry.key]
            : entry.value;
        final value = relationshipForPatient(entry.value);
        return '$label | ${value.isEmpty ? "Not specified" : value}';
      })
      .toSet()
      .join('\n');

  /// Compares user accounts using their Firebase UID.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel &&
          runtimeType == other.runtimeType &&
          uid == other.uid;

  /// Generates a hash code based on the user's UID.
  @override
  int get hashCode => uid.hashCode;
}
