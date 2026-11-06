import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../services/notification_identity.dart';
import '../services/schedule_time.dart';

/// A linked account's medication alert. The payload only identifies records;
/// the receiver must still verify the current account, links and latest action.
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

  static const type = 'medication_status';
  static const payloadPrefix = 'medication-status:';
  static const snoozeDuration = Duration(minutes: 10);
  static const _actions = {'taken', 'skipped', 'missed', 'snoozed'};
  static const _kinds = {'status', 'snooze_followup'};

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

  bool get isFollowup => notificationKind == 'snooze_followup';

  String get statusLabel => switch (action) {
    'taken' => 'Taken',
    'skipped' || 'missed' => 'Missed',
    _ => 'Snoozed',
  };

  /// All revisions of one medication replace the same tray entry. Including
  /// the recipient also isolates a shared phone after an account switch.
  int get id => notificationId(
    'medication-status:$recipientUid:$patientId:$medicationId',
  );

  String get eventKey => '$recipientUid:$actionId:$notificationKind';
  String get title => '$patientName • $medicationName';

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

  String toLocalPayload() => '$payloadPrefix${jsonEncode(toMap())}';

  static MedicationStatusNotification? fromLocalPayload(String? payload) {
    if (payload == null || !payload.startsWith(payloadPrefix)) return null;
    try {
      final parsed = jsonDecode(payload.substring(payloadPrefix.length));
      return parsed is Map<String, dynamic> ? tryParse(parsed) : null;
    } on FormatException {
      return null;
    }
  }

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

  /// Suppress out-of-order deliveries and replaced/cancelled snoozes. Callers
  /// obtain the latest revision from Firestore before invoking this policy.
  bool shouldAlert({
    required String latestActionId,
    required String latestAction,
    required int latestActionTime,
    required DateTime now,
    int? latestSnoozeUntil,
  }) {
    if (latestActionId != actionId ||
        latestAction != action ||
        latestActionTime != actionTime ||
        actionTime >
            now.add(const Duration(minutes: 5)).millisecondsSinceEpoch) {
      return false;
    }
    final defaultDeadline = latestActionTime + snoozeDuration.inMilliseconds;
    final currentDeadline =
        latestSnoozeUntil != null &&
            latestSnoozeUntil >= latestActionTime &&
            latestSnoozeUntil <= defaultDeadline
        ? latestSnoozeUntil
        : defaultDeadline;
    // A delayed initial snooze is obsolete when the follow-up becomes due.
    // This includes a message whose server lookup finishes after the deadline.
    if (!isFollowup) {
      return action != 'snoozed' ||
          now.millisecondsSinceEpoch < currentDeadline;
    }
    return action == 'snoozed' &&
        currentDeadline == snoozeUntil &&
        now.millisecondsSinceEpoch >= snoozeUntil!;
  }

  static String? _uid(Object? value) =>
      value is String &&
          value.isNotEmpty &&
          value.trim() == value &&
          value.length <= 128 &&
          !value.contains('/')
      ? value
      : null;

  static String? _name(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static String? _recordId(Object? value) {
    final text = value is int ? value.toString() : value;
    if (text is! String || !RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(text)) {
      return null;
    }
    final number = int.tryParse(text);
    return number != null && number <= 9007199254740991 ? text : null;
  }

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
