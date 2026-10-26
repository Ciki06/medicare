import '../models/medication_model.dart';
import 'appointment_reminder_state.dart';
import 'notification_identity.dart';
import 'reminder_audio_service.dart';

/// A native stop/swipe is tied to the exact patient and schedule occurrence.
/// An acknowledgment for an older schedule must not dismiss an edited one.
List<Appointment> applyAppointmentAlarmDismissals({
  required List<Appointment> appointments,
  required String patientId,
  required List<Map<String, dynamic>> dismissals,
}) => [
  for (final appointment in appointments)
    if (appointment.patientId == patientId &&
        appointment.status == 'scheduled' &&
        appointment.reminderAt != null &&
        !appointment.reminderViewed &&
        dismissals.any(
          (dismissal) =>
              dismissal['patientId'] == patientId &&
              dismissal['payload'] == 'appointment:${appointment.id}' &&
              dismissal['id'] ==
                  notificationId('apt:$patientId:${appointment.id}') &&
              dismissal['at'] ==
                  appointment.reminderAt?.millisecondsSinceEpoch &&
              dismissal['scheduleKey'] == appointment.reminderKey,
        ))
      Appointment.fromMap(appointment.id, {
        ...appointment.toMap(),
        'reminderViewedFor': appointment.reminderKey,
      })
    else
      appointment,
];

class AppointmentAlarmAcknowledgements {
  static Future<List<Appointment>> restore(
    String patientId,
    List<Appointment> appointments,
  ) async {
    if (!ReminderAudioService.android) return appointments;
    final dismissals = await ReminderAudioService.dismissedAppointments();
    final restored = applyAppointmentAlarmDismissals(
      appointments: appointments,
      patientId: patientId,
      dismissals: dismissals,
    );
    for (var i = 0; i < restored.length; i++) {
      if (!appointments[i].reminderViewed && restored[i].reminderViewed) {
        await AppointmentReminderState.remember(restored[i]);
      }
    }
    return restored;
  }
}
