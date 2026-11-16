/// Firebase relationships always carry Auth UIDs; SQLite resolves its own FKs.
class CloudRecordFields {
  static String patientUid(Map<String, dynamic> map) =>
      map['patientId'] as String;
  static String caregiverUid(Map<String, dynamic> map) =>
      map['caregiverId'] as String;
  // Convert the stored medication reference to the string used for document lookups in Dart.
  static String medicationKey(Map<String, dynamic> map) =>
      map['medicationId'].toString();
}
