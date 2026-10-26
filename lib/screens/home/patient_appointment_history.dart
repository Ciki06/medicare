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
  final firstDay = tz.TZDateTime(
    ScheduleTime.location,
    current.year,
    current.month,
    current.day - 6,
  );
  return appointments.where((appointment) {
    if (appointment.patientId != patientId ||
        appointment.status != 'completed') {
      return false;
    }
    final scheduledAt = appointment.scheduledAt;
    return scheduledAt != null &&
        !scheduledAt.isBefore(firstDay) &&
        !scheduledAt.isAfter(current);
  }).toList()..sort(Appointment.newestFirst);
}
