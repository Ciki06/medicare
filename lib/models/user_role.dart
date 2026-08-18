import 'package:flutter/material.dart';

enum UserRole { patient, caregiver, family, pharmacist }

extension UserRoleDetails on UserRole {
  String get label => switch (this) {
    UserRole.patient => 'Patient',
    UserRole.caregiver => 'Caregiver',
    UserRole.family => 'Family',
    UserRole.pharmacist => 'Pharmacist',
  };

  String get image => switch (this) {
    UserRole.patient => 'assets/ElderPeoplePic.jpg',
    UserRole.caregiver => 'assets/Caregiver.jpg',
    UserRole.family => 'assets/Family.jpg',
    UserRole.pharmacist => 'assets/Pharmacist.jpg',
  };

  Color get color => switch (this) {
    UserRole.patient => const Color(0xFF2E72B7),
    UserRole.caregiver => const Color(0xFF5F9D47),
    UserRole.family => const Color(0xFFE69A31),
    UserRole.pharmacist => const Color(0xFFE06F5D),
  };

  String get greetingName => switch (this) {
    UserRole.patient => 'Jane',
    UserRole.caregiver => 'Brandy',
    UserRole.family => 'Jane',
    UserRole.pharmacist => 'Alex',
  };
}
