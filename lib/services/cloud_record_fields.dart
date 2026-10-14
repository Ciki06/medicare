/// Firebase login identities stay in UID fields. Business ID fields are
/// integers; these accessors keep authentication/query UIDs explicit.
class CloudRecordFields {
  static String patientUid(Map<String, dynamic> map) =>
      (map['patient_uid'] ?? map['patientId']) as String;
  static String caregiverUid(Map<String, dynamic> map) =>
      (map['caregiver_uid'] ?? map['caregiverId']) as String;
  static String medicationKey(Map<String, dynamic> map) =>
      map['medicationId'].toString();

  static Map<String, dynamic> profileForLocal(Map<String, dynamic> map) => {
    ...map,
    if (map['caregiver_uid'] != null) 'caregiverId': map['caregiver_uid'],
    if (map['linkedPatientUids'] != null)
      'linkedPatientIds': map['linkedPatientUids'],
    if (map['linkedPatientUid'] != null)
      'linkedPatientId': map['linkedPatientUid'],
  };
}
