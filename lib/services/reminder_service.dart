import 'dart:async';
import 'package:flutter/material.dart';
import '../models/medication_action.dart';
import 'schedule_time.dart';
import '../models/medication_model.dart';

class MedicationReminder {
  final Medication medication;
  final DateTime scheduledTime;

  MedicationReminder({required this.medication, required this.scheduledTime});
}

class AppointmentReminder {
  final Appointment appointment;
  final DateTime scheduledTime;

  AppointmentReminder({required this.appointment, required this.scheduledTime});
}

class ReminderService extends ChangeNotifier {
  static final ReminderService _instance = ReminderService._();
  factory ReminderService() => _instance;
  ReminderService._();

  Timer? _timer;
  final Set<String> _firedToday = {};
  String _currentDate = '';
  List<Medication> _medications = [];
  List<Appointment> _appointments = [];
  final List<MedicationReminder> _activeReminders = [];
  final List<AppointmentReminder> _activeAppointmentReminders = [];
  final Map<String, int> _snoozeUntilMs = {};

  List<MedicationReminder> get activeReminders =>
      List.unmodifiable(_activeReminders);
  List<AppointmentReminder> get activeAppointmentReminders =>
      List.unmodifiable(_activeAppointmentReminders);

  void start({required List<Medication> medications}) {
    _medications = medications;
    _checkDateRollover();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    _tick();
  }

  void updateMedications(List<Medication> medications) {
    _medications = medications;
    _checkDateRollover();
    _tick();
  }

  void updateAppointments(List<Appointment> appointments) {
    _appointments = appointments;
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    stop();
    _medications = [];
    _appointments = [];
    _activeReminders.clear();
    _activeAppointmentReminders.clear();
    _firedToday.clear();
    _snoozeUntilMs.clear();
    _currentDate = '';
  }

  void snoozeMedication(String medId, int snoozeUntilMs) {
    _snoozeUntilMs[medId] = snoozeUntilMs;
    _activeReminders.removeWhere((r) => r.medication.id == medId);
    notifyListeners();
  }

  /// Re-seed in-memory snoozes from persisted actions so a snooze survives an
  /// app restart / process kill and still re-reminds after its window.
  void restoreSnoozes(List<MedicationAction> actions) {
    final nowMs = ScheduleTime.now().millisecondsSinceEpoch;
    for (final action in actions) {
      if (action.action != 'snoozed' || action.snoozedUntil == null) continue;
      final until = action.snoozedUntil!;
      if (until <= nowMs) continue;
      final existing = _snoozeUntilMs[action.medicationId];
      if (existing == null || until > existing) {
        _snoozeUntilMs[action.medicationId] = until;
      }
    }
  }

  void clearSnooze(String medId) {
    _snoozeUntilMs.remove(medId);
  }

  int? snoozeUntilMs(String medId) => _snoozeUntilMs[medId];

  bool isSnoozed(String medId) {
    final until = _snoozeUntilMs[medId];
    if (until == null) return false;
    if (ScheduleTime.now().millisecondsSinceEpoch >= until) {
      _snoozeUntilMs.remove(medId);
      return false;
    }
    return true;
  }

  void markHandled(String medId, DateTime scheduled) {
    final key = _reminderKey(medId, scheduled);
    _firedToday.add(key);
    _activeReminders.removeWhere((r) => r.medication.id == medId);
    _snoozeUntilMs.remove(medId);
    notifyListeners();
  }

  void markAppointmentHandled(String aptId, DateTime scheduled) {
    final key =
        'apt-$aptId-${scheduled.year}-${scheduled.month}-${scheduled.day}-${scheduled.hour}-${scheduled.minute}';
    _firedToday.add(key);
    _activeAppointmentReminders.removeWhere((r) => r.appointment.id == aptId);
    notifyListeners();
  }

  void _checkDateRollover() {
    final today = ScheduleTime.now().toString().substring(0, 10);
    if (today != _currentDate) {
      _currentDate = today;
      _firedToday.clear();
    }
  }

  String _reminderKey(String medId, DateTime scheduled) {
    return '$medId-${scheduled.year}-${scheduled.month}-${scheduled.day}-${scheduled.hour}-${scheduled.minute}';
  }

  void _tick() {
    _checkDateRollover();
    final now = ScheduleTime.now();
    final todayStr = now.toString().substring(0, 10);
    final nowMs = now.millisecondsSinceEpoch;

    for (final med in _medications) {
      if (!shouldShowToday(med, todayStr)) continue;

      final scheduled = _parseScheduledTime(med.time, now);
      if (scheduled == null) continue;

      final snoozeUntil = _snoozeUntilMs[med.id];
      if (snoozeUntil != null) {
        if (nowMs < snoozeUntil) {
          continue;
        }
        _snoozeUntilMs.remove(med.id);
        final alreadyActive = _activeReminders.any(
          (r) => r.medication.id == med.id,
        );
        if (!alreadyActive) {
          _activeReminders.add(
            MedicationReminder(medication: med, scheduledTime: scheduled),
          );
          notifyListeners();
        }
        continue;
      }

      final diff = now.difference(scheduled).inMinutes;
      if (diff >= 0 && diff < 2) {
        final key = _reminderKey(med.id, scheduled);
        if (!_firedToday.contains(key)) {
          _firedToday.add(key);
          final alreadyActive = _activeReminders.any(
            (r) => r.medication.id == med.id,
          );
          if (!alreadyActive) {
            _activeReminders.add(
              MedicationReminder(medication: med, scheduledTime: scheduled),
            );
            notifyListeners();
          }
        }
      }
    }

    for (final apt in _appointments) {
      final normalizedDate = apt.date.replaceAll('/', '-');
      final aptDate = DateTime.tryParse(normalizedDate);
      if (aptDate == null) continue;
      if (aptDate.year != now.year ||
          aptDate.month != now.month ||
          aptDate.day != now.day) {
        continue;
      }

      final scheduled = _parseScheduledTime(apt.time, now);
      if (scheduled == null) continue;

      final remindBefore = apt.remindBefore.clamp(0, 24 * 60);
      final remindAt = scheduled.subtract(Duration(minutes: remindBefore));

      final diff = now.difference(remindAt).inMinutes;
      if (diff >= 0 && diff < 2) {
        final key =
            'apt-${apt.id}-${scheduled.year}-${scheduled.month}-${scheduled.day}-${scheduled.hour}-${scheduled.minute}';
        if (!_firedToday.contains(key)) {
          _firedToday.add(key);
          final alreadyActive = _activeAppointmentReminders.any(
            (r) => r.appointment.id == apt.id,
          );
          if (!alreadyActive) {
            _activeAppointmentReminders.add(
              AppointmentReminder(appointment: apt, scheduledTime: remindAt),
            );
            notifyListeners();
          }
        }
      }
    }
  }

  static bool shouldShowToday(Medication med, String todayStr) =>
      med.isScheduledForDate(DateTime.parse(todayStr));
  static String formatTodayDate() => Medication.formatTodayDate();
  static String todayIso() => ScheduleTime.today();
  static DateTime? _parseScheduledTime(String timeStr, DateTime now) =>
      ScheduleTime.onDate(timeStr, now);
}
