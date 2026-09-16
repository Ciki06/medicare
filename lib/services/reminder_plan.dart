import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/medication_model.dart';
import 'notification_identity.dart';
import 'schedule_time.dart';

class PlannedReminder {
  const PlannedReminder(
    this.key,
    this.at,
    this.title,
    this.body,
    this.payload, {
    this.repeat,
    this.medication = true,
  });
  final String key, title, body, payload;
  final tz.TZDateTime at;
  final DateTimeComponents? repeat;
  final bool medication;
  int get id => notificationId(key);
}

List<PlannedReminder> planReminders(
  List<Medication> medications,
  List<Appointment> appointments,
  DateTime now,
) {
  final local = tz.TZDateTime.from(now, ScheduleTime.location);
  final plan = <PlannedReminder>[];
  for (final med in medications) {
    final frequencies = med.days.map((s) => s.toLowerCase()).toList();
    final daily = frequencies.isEmpty || frequencies.contains('daily');
    final weekly =
        frequencies.contains('weekly') ||
        frequencies.any(
          (s) => [
            'monday',
            'tuesday',
            'wednesday',
            'thursday',
            'friday',
            'saturday',
            'sunday',
          ].contains(s),
        );
    final monthly = frequencies.contains('monthly');
    final anchor = DateTime.tryParse(med.startDate ?? '');
    // Repeating iOS calendar triggers ignore the start date. Use dated
    // occurrences until the regimen has started, then switch on reconciliation.
    final futureStart =
        anchor != null &&
        ScheduleTime.dateKey(local).compareTo(med.startDate!) < 0;
    final repeated = <int>{};
    for (var offset = 0; offset < 400; offset++) {
      final date = tz.TZDateTime(
        ScheduleTime.location,
        local.year,
        local.month,
        local.day + offset,
      );
      if (!med.isScheduledForDate(date)) continue;
      final at = ScheduleTime.onDate(med.time, date);
      if (at == null || !at.isAfter(local)) continue;
      final slot = weekly ? date.weekday : 0;
      if (!futureStart && (daily || weekly || monthly) && !repeated.add(slot)) {
        continue;
      }
      final recurrence = futureStart
          ? null
          : daily
          ? DateTimeComponents.time
          : weekly
          ? DateTimeComponents.dayOfWeekAndTime
          : monthly
          ? DateTimeComponents.dayOfMonthAndTime
          : null;
      plan.add(
        PlannedReminder(
          'med:${med.patientId}:${med.id}:${recurrence == null ? ScheduleTime.dateKey(date) : slot}',
          at,
          'Medication Reminder',
          'Time to take ${med.name} (${med.dosage})',
          med.id,
          repeat: recurrence,
        ),
      );
      if ((!futureStart && (daily || monthly)) ||
          frequencies.contains('once')) {
        break;
      }
    }
  }
  for (final apt in appointments) {
    if (apt.status != 'scheduled') continue;
    final date = DateTime.tryParse(apt.date.replaceAll('/', '-'));
    if (date == null) continue;
    final time = ScheduleTime.onDate(apt.time, date);
    if (time == null) continue;
    final at = time.subtract(
      Duration(minutes: apt.remindBefore.clamp(0, 1440)),
    );
    if (!at.isAfter(local)) continue;
    plan.add(
      PlannedReminder(
        'apt:${apt.patientId}:${apt.id}',
        at,
        'Appointment Reminder',
        '${apt.title} at ${apt.displayTime} ${apt.location}',
        'appointment:${apt.id}',
        medication: false,
      ),
    );
  }
  plan.sort((a, b) => a.at.compareTo(b.at));
  return plan;
}
