/// Business IDs are identical in SQLite and Firestore. Account integer keys are
/// local only and are never sent to Firebase.
class LocalIdSchema {
  static const identityTables = {
    'medications': ('Medications', 'medication_id'),
    'appointments': ('Appointments', 'appointment_id'),
    'medication_actions': ('Medication_Action', 'id'),
    'moods': ('Mood', 'id'),
    'refill_requests': ('Refill_Request', 'id'),
  };

  static bool validId(int value) => value > 0 && value <= 9007199254740991;

  static int requireId(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || !validId(parsed) || value != parsed.toString()) {
      throw ArgumentError('A positive integer business record ID is required.');
    }
    return parsed;
  }
}
