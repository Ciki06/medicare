import '../models/medication_model.dart';
import 'notification_identity.dart';

/// A delivered appointment is no longer in the future scheduling plan. Its
/// notification must nevertheless survive reconciliation until acknowledged.
/// This returns retained IDs only; callers must not post the alert again.
Set<int> retainedAppointmentNotificationIds(
  Iterable<Appointment> appointments,
  DateTime now,
) => appointments
    .where(
      (appointment) =>
          appointment.status == 'scheduled' &&
          !appointment.reminderViewed &&
          appointment.reminderAt != null &&
          !appointment.reminderAt!.isAfter(now),
    )
    .map(
      (appointment) =>
          notificationId('apt:${appointment.patientId}:${appointment.id}'),
    )
    .toSet();
