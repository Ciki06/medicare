/// Firebase relationships always carry Auth UIDs; SQLite resolves its own FKs.
class CloudRecordFields {
  static String patientUid(Map<String, dynamic> map) =>
      map['patientId'] as String;
  static String caregiverUid(Map<String, dynamic> map) =>
      map['caregiverId'] as String;
  static String medicationKey(Map<String, dynamic> map) =>
      map['medicationId'].toString();
}
