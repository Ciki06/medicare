import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/medication_action.dart';
import '../models/medication_model.dart';
import 'notification_identity.dart';

class PendingSnoozeMigration {
  const PendingSnoozeMigration(this.medication, this.action);

  final Medication medication;
  final MedicationAction action;

  int get id => notificationId('snooze:${medication.id}');
  int get until => action.snoozedUntil!;
  DateTime get when => DateTime.fromMillisecondsSinceEpoch(until);
  (int, int) get key => (id, until);
}

/// Updates only an existing future alarm. Delivered, acknowledged and expired
/// reminders must never be recreated while migrating notification channels.
List<PendingSnoozeMigration> pendingSnoozeMigrations({
  required Iterable<Medication> medications,
  required Iterable<MedicationAction> actions,
  required Iterable<PendingNotificationRequest> pending,
  required String patientId,
  required DateTime now,
}) {
  final latest = <String, MedicationAction>{};
  for (final action in actions.where(
    (action) => action.patientId == patientId,
  )) {
    final previous = latest[action.medicationId];
    // A same-millisecond acknowledgement wins over a snooze conservatively.
    if (previous == null ||
        action.timestamp > previous.timestamp ||
        action.timestamp == previous.timestamp &&
            previous.action == 'snoozed' &&
            action.action != 'snoozed') {
      latest[action.medicationId] = action;
    }
  }
  final pendingPayloads = {
    for (final request in pending) request.id: request.payload,
  };
  final candidates = <PendingSnoozeMigration>[];
  for (final medication in medications) {
    if (medication.patientId != patientId || medication.isCompleted) continue;
    final action = latest[medication.id];
    final until = action?.snoozedUntil;
    if (action == null ||
        action.action != 'snoozed' ||
        until == null ||
        until <= now.millisecondsSinceEpoch) {
      continue;
    }
    final candidate = PendingSnoozeMigration(medication, action);
    if (pendingPayloads[candidate.id] == medication.id) {
      candidates.add(candidate);
    }
  }
  return candidates;
}
