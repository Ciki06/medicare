import '../../models/medication_action.dart';

/// A display-only view of the patient's existing medication activity.
/// Distinct doses and snoozes remain separate; storage and status are unchanged.
List<MedicationAction> recentPatientMedicationActivity({
  required Iterable<MedicationAction> actions,
  required String patientId,
  int recentLimit = 5,
}) {
  const supportedActions = {'taken', 'skipped', 'missed', 'snoozed'};
  // Keep supported actions for this patient and show the newest first.
  final sorted =
      actions
          .where(
            (action) =>
                action.patientId == patientId &&
                supportedActions.contains(action.action),
          )
          .toList()
        ..sort((a, b) {
          final byTime = b.timestamp.compareTo(a.timestamp);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
  // Check both record IDs and event details so duplicate rows appear only once.
  final eventIds = <(String, String)>{};
  final events = <(String, String, String, int, int?)>{};
  final uniqueActions = <MedicationAction>[];
  for (final action in sorted) {
    // Detect a repeated copy of the same saved record using the patient and record ID.
    final duplicateId =
        action.id.trim().isNotEmpty &&
        !eventIds.add((action.patientId, action.id));
    // Compare the medication, action, and timing to catch duplicate copies with different IDs.
    final duplicateEvent = !events.add((
      action.patientId,
      action.medicationId,
      action.action,
      action.timestamp,
      action.snoozedUntil,
    ));
    if (!duplicateId && !duplicateEvent) uniqueActions.add(action);
  }
  // Limit the display list after removing duplicates.
  return uniqueActions.take(recentLimit).toList();
}
