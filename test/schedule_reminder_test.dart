import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:medicare/models/medication_model.dart';
import 'package:medicare/services/schedule_time.dart';
import 'package:medicare/services/reminder_plan.dart';

Medication medicine(
  String id, {
  String time = '8:00 PM',
  String frequency = 'Daily',
  String? start = '2026-09-15',
  int interval = 1,
}) => Medication(
  id: id,
  name: id,
  dosage: '1 pill',
  time: time,
  days: [frequency],
  patientId: 'patient',
  patientName: 'Patient',
  caregiverId: 'caregiver',
  startDate: start,
  intervalDays: interval,
);

void main() {
  test('legacy 12-hour times normalize and retain the same UTC+8 instant', () {
    expect(ScheduleTime.normalize('12:05 AM'), '00:05');
    expect(ScheduleTime.normalize('12:05 PM'), '12:05');
    expect(ScheduleTime.display('20:00'), '8:00 PM');
    expect(ScheduleTime.display('00:00'), '12:00 AM');
    expect(ScheduleTime.display('12:00'), '12:00 PM');
    expect(ScheduleTime.display('8:05 PM'), '8:05 PM');
    for (final invalid in ['24:00', '8:70', '13:00 PM', 'nonsense']) {
      expect(ScheduleTime.parse(invalid), isNull);
    }
    final scheduled = ScheduleTime.onDate('8:00 PM', DateTime(2026, 9, 15))!;
    expect(scheduled.toUtc(), DateTime.utc(2026, 9, 15, 12));
    expect(scheduled.timeZoneOffset, const Duration(hours: 8));
  });

  test('notification IDs survive reorder and medication deletion', () {
    final now = DateTime.utc(2026, 9, 15, 0);
    final a = medicine('a'), b = medicine('b');
    final before = {
      for (final p in planReminders([a, b], [], now)) p.payload: p.id,
    };
    final after = {
      for (final p in planReminders([b, a], [], now)) p.payload: p.id,
    };
    expect(after, before);
    expect(planReminders([b], [], now).single.id, before['b']);
    expect(planReminders([b], [], now).single.repeat, DateTimeComponents.time);
  });

  test('once, weekly, monthly and intervals honor start date', () {
    final once = medicine('once', frequency: 'Once');
    expect(once.isScheduledForDate(DateTime(2026, 9, 15)), isTrue);
    expect(once.isScheduledForDate(DateTime(2026, 9, 16)), isFalse);
    final weekly = medicine('weekly', frequency: 'Weekly');
    expect(weekly.isScheduledForDate(DateTime(2026, 9, 22)), isTrue);
    expect(weekly.isScheduledForDate(DateTime(2026, 9, 16)), isFalse);
    final every = medicine('interval', frequency: 'Every X days', interval: 3);
    expect(every.isScheduledForDate(DateTime(2026, 9, 18)), isTrue);
    expect(every.isScheduledForDate(DateTime(2026, 9, 17)), isFalse);
    expect(every.isScheduledForDate(DateTime(2026, 9, 12)), isFalse);
    final monthly = medicine(
      'monthly',
      frequency: 'Monthly',
      start: '2026-01-31',
    );
    expect(monthly.isScheduledForDate(DateTime(2026, 2, 28)), isFalse);
    expect(monthly.isScheduledForDate(DateTime(2026, 3, 31)), isTrue);
  });

  test('future schedules are dated so calendar repeats cannot start early', () {
    final rows = planReminders(
      [medicine('future', start: '2026-09-20')],
      [],
      DateTime.utc(2026, 9, 15),
    );
    expect(rows.first.at.day, 20);
    expect(rows.first.repeat, isNull);
  });

  test(
    'appointments beyond tomorrow are scheduled and AM/PM parses correctly',
    () {
      Appointment appointment(String id, String status) => Appointment(
        id: id,
        title: 'Checkup',
        date: '2026-10-20',
        time: '3:30 PM',
        location: 'Clinic',
        patientId: 'patient',
        patientName: 'Patient',
        caregiverId: 'caregiver',
        status: status,
        remindBefore: 30,
      );
      final rows = planReminders([], [
        appointment('future', 'scheduled'),
        appointment('done', 'completed'),
      ], DateTime.utc(2026, 9, 15));
      expect(rows.length, 1);
      expect(rows.single.at.toUtc(), DateTime.utc(2026, 10, 20, 7));
    },
  );
}
