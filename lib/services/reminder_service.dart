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
  ReminderService._({DateTime Function()? now})
    : _now = now ?? ScheduleTime.now;

  @visibleForTesting
  ReminderService.forTesting({required DateTime Function() now}) : _now = now;

  final DateTime Function() _now;
  Timer? _timer;
  bool _running = false;
  final Set<String> _firedToday = {};
  final Set<String> _handledToday = {};
  final Set<String> _firedAppointments = {};
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
    _running = true;
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
    _running = false;
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
    _handledToday.clear();
    _firedAppointments.clear();
    _snoozeUntilMs.clear();
    _currentDate = '';
  }

  void snoozeMedication(String medId, int snoozeUntilMs) {
    _handledToday.remove(medId);
    _snoozeUntilMs[medId] = snoozeUntilMs;
    _activeReminders.removeWhere((r) => r.medication.id == medId);
    _scheduleNextCheck();
    notifyListeners();
  }

  /// Re-seed in-memory snoozes from persisted actions so a snooze survives an
  /// app restart / process kill and still re-reminds after its window.
  void restoreSnoozes(List<MedicationAction> actions) {
    _checkDateRollover();
    final now = _now();
    final nowMs = now.millisecondsSinceEpoch;
    final todayMs = ScheduleTime.onDate('00:00', now)!.millisecondsSinceEpoch;
    final latest = <String, MedicationAction>{};
    for (final action in actions) {
      final previous = latest[action.medicationId];
      if (previous == null || action.timestamp > previous.timestamp) {
        latest[action.medicationId] = action;
      }
    }
    final activeCount = _activeReminders.length;
    for (final action in latest.values) {
      if (action.action == 'snoozed' && action.snoozedUntil != null) {
        _handledToday.remove(action.medicationId);
        final until = action.snoozedUntil!;
        if (until > nowMs) {
          _snoozeUntilMs[action.medicationId] = until;
          _activeReminders.removeWhere(
            (r) => r.medication.id == action.medicationId,
          );
        }
      } else {
        _snoozeUntilMs.remove(action.medicationId);
        if (action.timestamp >= todayMs) {
          _handledToday.add(action.medicationId);
          for (final medication in _medications.where(
            (m) => m.id == action.medicationId,
          )) {
            final scheduled = ScheduleTime.onDate(medication.time, now);
            if (scheduled != null) {
              _firedToday.add(_reminderKey(medication.id, scheduled));
            }
          }
          _activeReminders.removeWhere(
            (r) => r.medication.id == action.medicationId,
          );
        }
      }
    }
    if (activeCount != _activeReminders.length) notifyListeners();
    _tick();
  }

  void clearSnooze(String medId) {
    _snoozeUntilMs.remove(medId);
  }

  int? snoozeUntilMs(String medId) => _snoozeUntilMs[medId];

  bool isSnoozed(String medId) {
    final until = _snoozeUntilMs[medId];
    if (until == null) return false;
    if (_now().millisecondsSinceEpoch >= until) {
      _snoozeUntilMs.remove(medId);
      return false;
    }
    return true;
  }

  void markHandled(String medId, DateTime scheduled) {
    final key = _reminderKey(medId, scheduled);
    _firedToday.add(key);
    _handledToday.add(medId);
    _activeReminders.removeWhere((r) => r.medication.id == medId);
    _snoozeUntilMs.remove(medId);
    notifyListeners();
  }

  void markAppointmentHandled(String aptId, DateTime scheduled) {
    for (final appointment in _appointments.where((apt) => apt.id == aptId)) {
      _firedAppointments.add(_appointmentReminderKey(appointment));
    }
    _activeAppointmentReminders.removeWhere((r) => r.appointment.id == aptId);
    notifyListeners();
  }

  void _checkDateRollover() {
    final today = ScheduleTime.dateKey(_now());
    if (today != _currentDate) {
      _currentDate = today;
      _firedToday.clear();
      _handledToday.clear();
    }
  }

  String _reminderKey(String medId, DateTime scheduled) {
    return '$medId-${scheduled.year}-${scheduled.month}-${scheduled.day}-${scheduled.hour}-${scheduled.minute}';
  }

  String _appointmentReminderKey(Appointment appointment) =>
      'apt-${appointment.id}-${appointment.reminderKey}';

  void _tick() {
    _checkDateRollover();
    final now = _now();
    final todayStr = now.toString().substring(0, 10);
    final nowMs = now.millisecondsSinceEpoch;

    final activeCount =
        _activeReminders.length + _activeAppointmentReminders.length;
    _activeReminders.removeWhere(
      (reminder) => !_medications.any(
        (medication) =>
            medication.id == reminder.medication.id &&
            shouldShowToday(medication, todayStr) &&
            ScheduleTime.onDate(
                  medication.time,
                  now,
                )?.isAtSameMomentAs(reminder.scheduledTime) ==
                true,
      ),
    );
    _activeAppointmentReminders.removeWhere(
      (reminder) => !_appointments.any(
        (appointment) =>
            appointment.id == reminder.appointment.id &&
            appointment.status == 'scheduled' &&
            !appointment.reminderViewed &&
            appointment.reminderKey == reminder.appointment.reminderKey,
      ),
    );
    if (activeCount !=
        _activeReminders.length + _activeAppointmentReminders.length) {
      notifyListeners();
    }

    for (final med in _medications) {
      if (!shouldShowToday(med, todayStr)) continue;
      if (_handledToday.contains(med.id)) continue;

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

      // inMinutes truncates -59 seconds to zero, showing a future minute
      // early. Compare the complete duration before considering the grace window.
      final elapsed = now.difference(scheduled);
      if (!elapsed.isNegative && elapsed < const Duration(minutes: 2)) {
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
      if (apt.status != 'scheduled' || apt.reminderViewed) continue;
      final scheduled = apt.scheduledAt;
      final remindAt = apt.reminderAt;
      if (scheduled == null || remindAt == null) continue;
      final elapsed = now.difference(remindAt);
      // Unviewed appointments remain visible until explicitly acknowledged.
      if (!elapsed.isNegative) {
        final key = _appointmentReminderKey(apt);
        if (!_firedAppointments.contains(key)) {
          _firedAppointments.add(key);
          final alreadyActive = _activeAppointmentReminders.any(
            (r) => r.appointment.id == apt.id,
          );
          if (!alreadyActive) {
            _activeAppointmentReminders.add(
              AppointmentReminder(appointment: apt, scheduledTime: scheduled),
            );
            notifyListeners();
          }
        }
      }
    }
    _scheduleNextCheck();
  }

  void _scheduleNextCheck() {
    _timer?.cancel();
    if (!_running) return;
    final now = _now();
    // The short safety poll also detects wall-clock changes. A nearer due time
    // gets its own timer, so a reminder is never delayed by the poll interval.
    var next = now.add(const Duration(seconds: 30));
    void include(DateTime? at) {
      if (at != null && at.isAfter(now) && at.isBefore(next)) next = at;
    }

    for (final medication in _medications) {
      if (medication.isScheduledForDate(now)) {
        include(ScheduleTime.onDate(medication.time, now));
      }
    }
    for (final until in _snoozeUntilMs.values) {
      include(DateTime.fromMillisecondsSinceEpoch(until));
    }
    for (final appointment in _appointments) {
      if (appointment.status == 'scheduled' && !appointment.reminderViewed) {
        include(appointment.reminderAt);
      }
    }
    _timer = Timer(next.difference(now), _tick);
  }

  static bool shouldShowToday(Medication med, String todayStr) =>
      med.isScheduledForDate(DateTime.parse(todayStr));
  static String formatTodayDate() => Medication.formatTodayDate();
  static String todayIso() => ScheduleTime.today();
  static DateTime? _parseScheduledTime(String timeStr, DateTime now) =>
      ScheduleTime.onDate(timeStr, now);
}
