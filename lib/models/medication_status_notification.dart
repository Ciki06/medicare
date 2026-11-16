import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../services/notification_identity.dart';
import '../services/schedule_time.dart';

/// Manages medication status notifications sent to linked accounts.
class MedicationStatusNotification {
  const MedicationStatusNotification._({
    required this.recipientUid,
    required this.patientId,
    required this.medicationId,
    required this.actionId,
    required this.action,
    required this.actionTime,
    required this.notificationKind,
    required this.patientName,
    required this.medicationName,
    this.snoozeUntil,
  });

  /// Defines notification types, actions, and snooze duration.
  static const type = 'medication_status';
  static const payloadPrefix = 'medication-status:';
  static const snoozeDuration = Duration(minutes: 10);
  static const _actions = {'taken', 'skipped', 'missed', 'snoozed'};
  static const _kinds = {'status', 'snooze_followup'};

  // Stores the notification and medication action details.
  final String recipientUid;
  final String patientId;
  final String medicationId;
  final String actionId;
  final String action;
  final int actionTime;
  final String notificationKind;
  final String patientName;
  final String medicationName;
  final int? snoozeUntil;

  /// Checks whether the notification is a snooze follow-up.
  bool get isFollowup => notificationKind == 'snooze_followup';

  /// Converts medication actions into readable status labels
  String get statusLabel => switch (action) {
    'taken' => 'Taken',
    'skipped' || 'missed' => 'Missed',
    _ => 'Snoozed',
  };

  /// Generates a consistent notification ID for each medication and recipient.
  int get id => notificationId(
    'medication-status:$recipientUid:$patientId:$medicationId',
  );

  String get eventKey => '$recipientUid:$actionId:$notificationKind';
  String get title => '$patientName • $medicationName';

  /// Creates the notification message based on the medication action.
  String get body {
    if (isFollowup) {
      return '$patientName has not marked $medicationName as taken. '
          'Snooze follow-up due ${_displayTime(snoozeUntil!)}.';
    }
    final sentence = switch (action) {
      'taken' => '$patientName has taken their medication.',
      'skipped' || 'missed' => '$patientName has missed their medication.',
      _ => '$patientName has snoozed their medication reminder.',
    };
    return '$sentence $statusLabel at ${_displayTime(actionTime)}.';
  }

  /// Converts the notification time into Malaysia's local time.
  static String _displayTime(int milliseconds) {
    // ScheduleTime uses Malaysia time for every care-circle schedule, even
    // when linked accounts have different phone timezone settings.
    final local = tz.TZDateTime.fromMillisecondsSinceEpoch(
      ScheduleTime.location,
      milliseconds,
    );
    return '${ScheduleTime.dateKey(local)} '
        '${ScheduleTime.display('${local.hour}:${local.minute.toString().padLeft(2, '0')}')}';
  }

  Map<String, dynamic> toMap() => {
    'type': type,
    'recipientUid': recipientUid,
    'patientId': patientId,
    'medicationId': medicationId,
    'actionId': actionId,
    'action': action,
    'actionTime': actionTime,
    'notificationKind': notificationKind,
    'patientName': patientName,
    'medicationName': medicationName,
    if (snoozeUntil != null) 'snoozeUntil': snoozeUntil,
  };

  /// Creates a copy of the notification with updated names.
  MedicationStatusNotification withNames({
    required String patientName,
    required String medicationName,
  }) => MedicationStatusNotification._(
    recipientUid: recipientUid,
    patientId: patientId,
    medicationId: medicationId,
    actionId: actionId,
    action: action,
    actionTime: actionTime,
    notificationKind: notificationKind,
    patientName: _name(patientName) ?? this.patientName,
    medicationName: _name(medicationName) ?? this.medicationName,
    snoozeUntil: snoozeUntil,
  );

  /// Converts notification data into a JSON payload.
  String toLocalPayload() => '$payloadPrefix${jsonEncode(toMap())}';

  /// Reads the data saved with a local notification.
  static MedicationStatusNotification? fromLocalPayload(String? payload) {
    if (payload == null || !payload.startsWith(payloadPrefix)) return null;
    try {
      final parsed = jsonDecode(payload.substring(payloadPrefix.length));
      return parsed is Map<String, dynamic> ? tryParse(parsed) : null;
    } on FormatException {
      return null;
    }
  }

  /// Validates notification data before creating a notification object.
  static MedicationStatusNotification? tryParse(Map<String, dynamic> data) {
    if (data['type'] != type) return null;
    final recipientUid = _uid(data['recipientUid']);
    final patientId = _uid(data['patientId']);
    final medicationId = _recordId(data['medicationId']);
    final actionId = _recordId(data['actionId']);
    final action = data['action'];
    final kind = data['notificationKind'];
    final actionTime = _timestamp(data['actionTime']);
    final snoozeUntil = data['snoozeUntil'] == null
        ? null
        : _timestamp(data['snoozeUntil']);
    final patientName = _name(data['patientName']);
    final medicationName = _name(data['medicationName']);

    /// Rejects missing, invalid, or inconsistent notification details.
    if (recipientUid == null ||
        patientId == null ||
        recipientUid == patientId ||
        medicationId == null ||
        actionId == null ||
        !_actions.contains(action) ||
        !_kinds.contains(kind) ||
        actionTime == null ||
        patientName == null ||
        medicationName == null ||
        (data['snoozeUntil'] != null && snoozeUntil == null) ||
        (kind == 'snooze_followup' &&
            (action != 'snoozed' || snoozeUntil == null)) ||
        (snoozeUntil != null && snoozeUntil < actionTime)) {
      return null;
    }
    return MedicationStatusNotification._(
      recipientUid: recipientUid,
      patientId: patientId,
      medicationId: medicationId,
      actionId: actionId,
      action: action as String,
      actionTime: actionTime,
      notificationKind: kind as String,
      patientName: patientName,
      medicationName: medicationName,
      snoozeUntil: snoozeUntil,
    );
  }

  /// Checks whether a notification is still valid before showing it.
  bool shouldAlert({
    required String latestActionId,
    required String latestAction,
    required int latestActionTime,
    required DateTime now,
    int? latestSnoozeUntil,
  }) {
    /// Prevents outdated or mismatched medication notifications.
    if (latestActionId != actionId ||
        latestAction != action ||
        latestActionTime != actionTime ||
        actionTime >
            now.add(const Duration(minutes: 5)).millisecondsSinceEpoch) {
      return false;
    }

    /// Calculates the snooze follow-up time.
    final defaultDeadline = latestActionTime + snoozeDuration.inMilliseconds;
    final currentDeadline =
        latestSnoozeUntil != null &&
            latestSnoozeUntil >= latestActionTime &&
            latestSnoozeUntil <= defaultDeadline
        ? latestSnoozeUntil
        : defaultDeadline;

    /// Stops showing the initial snooze notification after its deadline.
    if (!isFollowup) {
      return action != 'snoozed' ||
          now.millisecondsSinceEpoch < currentDeadline;
    }

    /// Shows the follow-up only when the snooze period has ended.
    return action == 'snoozed' &&
        currentDeadline == snoozeUntil &&
        now.millisecondsSinceEpoch >= snoozeUntil!;
  }

  /// Checks whether the user ID has a valid format.
  static String? _uid(Object? value) =>
      value is String &&
          value.isNotEmpty &&
          value.trim() == value &&
          value.length <= 128 &&
          !value.contains('/')
      ? value
      : null;

  /// Removes extra spaces and checks for an empty name.
  static String? _name(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  /// Validates the medication and action record IDs.
  static String? _recordId(Object? value) {
    final text = value is int ? value.toString() : value;
    if (text is! String || !RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(text)) {
      return null;
    }
    final number = int.tryParse(text);
    return number != null && number <= 9007199254740991 ? text : null;
  }

  /// Checks whether the timestamp is a valid positive value.
  static int? _timestamp(Object? value) {
    final number = value is int
        ? value
        : value is String && RegExp(r'^[1-9][0-9]*$').hasMatch(value)
        ? int.tryParse(value)
        : null;
    return number != null && number > 0 && number <= 8640000000000000
        ? number
        : null;
  }
}
