import 'package:flutter/material.dart';

/// Defines the four user roles supported by the application.
enum UserRole { patient, caregiver, family, pharmacist }

/// Provides display information for each user role.
extension UserRoleDetails on UserRole {
  // Returns the display name of each user role.
  String get label => switch (this) {
    UserRole.patient => 'Patient',
    UserRole.caregiver => 'Caregiver',
    UserRole.family => 'Family',
    UserRole.pharmacist => 'Pharmacist',
  };

  /// Assigns an image to represent each user role.
  String get image => switch (this) {
    UserRole.patient => 'assets/ElderPeoplePic.jpg',
    UserRole.caregiver => 'assets/Caregiver.jpg',
    UserRole.family => 'assets/Family.jpg',
    UserRole.pharmacist => 'assets/Pharmacist.jpg',
  };

  /// Sets a different theme color for each user role.
  Color get color => switch (this) {
    UserRole.patient => const Color(0xFF2E72B7),
    UserRole.caregiver => const Color(0xFF5F9D47),
    UserRole.family => const Color(0xFFE69A31),
    UserRole.pharmacist => const Color(0xFFE06F5D),
  };

  /// Provides a default greeting name for each user role.
  String get greetingName => switch (this) {
    UserRole.patient => 'Jane',
    UserRole.caregiver => 'Brandy',
    UserRole.family => 'Jane',
    UserRole.pharmacist => 'Alex',
  };
}
