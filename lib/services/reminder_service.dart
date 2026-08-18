import 'dart:async';
import 'package:flutter/material.dart';
import '../models/medication_model.dart';

class MedicationReminder {
  final Medication medication;
  final DateTime scheduledTime;

  MedicationReminder({required this.medication, required this.scheduledTime});
}

class ReminderService extends ChangeNotifier {
  static final ReminderService _instance = ReminderService._();
  factory ReminderService() => _instance;
  ReminderService._();

  Timer? _timer;
  final Set<String> _firedToday = {};
  String _currentDate = '';
  List<Medication> _medications = [];
  final List<MedicationReminder> _activeReminders = [];
  final Map<String, int> _snoozeUntilMs = {};

  List<MedicationReminder> get activeReminders => List.unmodifiable(_activeReminders);

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

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void snoozeMedication(String medId, int snoozeUntilMs) {
    _snoozeUntilMs[medId] = snoozeUntilMs;
    _activeReminders.removeWhere((r) => r.medication.id == medId);
    notifyListeners();
  }

  void clearSnooze(String medId) {
    _snoozeUntilMs.remove(medId);
  }

  bool isSnoozed(String medId) {
    final until = _snoozeUntilMs[medId];
    if (until == null) return false;
    if (DateTime.now().millisecondsSinceEpoch >= until) {
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

  void _checkDateRollover() {
    final today = DateTime.now().toString().substring(0, 10);
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
    final now = DateTime.now();
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
        final alreadyActive = _activeReminders.any((r) => r.medication.id == med.id);
        if (!alreadyActive) {
          _activeReminders.add(MedicationReminder(
            medication: med,
            scheduledTime: scheduled,
          ));
          notifyListeners();
        }
        continue;
      }

      final diff = now.difference(scheduled).inMinutes;
      if (diff >= 0 && diff < 2) {
        final key = _reminderKey(med.id, scheduled);
        if (!_firedToday.contains(key)) {
          _firedToday.add(key);
          final alreadyActive = _activeReminders.any((r) => r.medication.id == med.id);
          if (!alreadyActive) {
            _activeReminders.add(MedicationReminder(
              medication: med,
              scheduledTime: scheduled,
            ));
            notifyListeners();
          }
        }
      }
    }
  }

  static bool shouldShowToday(Medication med, String todayStr) {
    final days = med.days.map((d) => d.toLowerCase()).toList();
    if (days.contains('daily') || days.isEmpty) return true;

    final today = DateTime.parse(todayStr);
    final weekdayNames = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final todayName = weekdayNames[today.weekday - 1];

    if (days.any((d) => d == todayName)) return true;

    if (days.any((d) => d.startsWith('every'))) {
      return true;
    }

    return false;
  }

  static String formatTodayDate() {
    final now = DateTime.now();
    final months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[now.month]} ${now.day}, ${now.year}';
  }

  static String todayIso() {
    return DateTime.now().toString().substring(0, 10);
  }

  static DateTime? _parseScheduledTime(String timeStr, DateTime now) {
    try {
      final cleaned = timeStr.trim();
      final isPM = cleaned.toUpperCase().contains('PM');
      final isAM = cleaned.toUpperCase().contains('AM');

      final withoutAmPm = cleaned
          .replaceAll(RegExp(r'[AaPp][Mm]'), '')
          .trim();
      final parts = withoutAmPm.split(':');
      if (parts.length != 2) return null;

      var hour = int.parse(parts[0].trim());
      final minute = int.parse(parts[1].trim());

      if (isPM && hour != 12) hour += 12;
      if (isAM && hour == 12) hour = 0;

      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (_) {
      return null;
    }
  }
}
