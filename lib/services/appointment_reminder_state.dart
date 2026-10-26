import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_model.dart';

/// Supplements the existing SQLite schedule cache without a database migration.
/// The appointment document remains the shared source for viewed/completed state.
class AppointmentReminderState {
  static String _key(String patientId, String id) =>
      'appointment_viewed_v1:${Uri.encodeComponent(patientId)}:${Uri.encodeComponent(id)}';

  static Future<void> remember(Appointment appointment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(appointment.patientId, appointment.id),
      appointment.reminderKey,
    );
  }

  static Future<List<Appointment>> restore(
    String patientId,
    List<Appointment> appointments,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <Appointment>[];
    for (final appointment in appointments) {
      if (appointment.patientId != patientId) {
        throw StateError('An appointment cache must belong to the patient.');
      }
      final key = _key(patientId, appointment.id);
      if (appointment.reminderViewed) {
        await prefs.setString(key, appointment.reminderKey);
        result.add(appointment);
      } else if (prefs.getString(key) == appointment.reminderKey) {
        result.add(
          Appointment.fromMap(appointment.id, {
            ...appointment.toMap(),
            'reminderViewedFor': appointment.reminderKey,
          }),
        );
      } else {
        result.add(appointment);
      }
    }
    return result;
  }
}
