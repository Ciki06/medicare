import 'package:timezone/timezone.dart' as tz;

import '../../models/medication_model.dart';
import '../../services/schedule_time.dart';

/// Display completed appointments from today and the preceding six days.
/// The existing records have a scheduled time, but no completion timestamp.
/// Filtering uses that scheduled time in the same timezone as the reminders.
List<Appointment> recentCompletedPatientAppointments({
  required Iterable<Appointment> appointments,
  required String patientId,
  DateTime? now,
}) {
  final current = tz.TZDateTime.from(
    now ?? ScheduleTime.now(),
    ScheduleTime.location,
  );
  // Start at midnight six days ago so the list covers seven calendar days.
  final firstDay = tz.TZDateTime(
    ScheduleTime.location,
    current.year,
    current.month,
    current.day - 6,
  );
  // Include only completed appointments for this patient and order the matches newest first.
  return appointments.where((appointment) {
    if (appointment.patientId != patientId ||
        appointment.status != 'completed') {
      return false;
    }
    // Use the scheduled time to decide whether this completed appointment belongs in the recent list.
    final scheduledAt = appointment.scheduledAt;
    return scheduledAt != null &&
        !scheduledAt.isBefore(firstDay) &&
        !scheduledAt.isAfter(current);
  }).toList()..sort(Appointment.newestFirst);
}
