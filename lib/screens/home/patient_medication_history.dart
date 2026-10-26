import '../../models/medication_action.dart';

/// A display-only view of the patient's existing medication activity.
/// Distinct doses and snoozes remain separate; storage and status are unchanged.
List<MedicationAction> recentPatientMedicationActivity({
  required Iterable<MedicationAction> actions,
  required String patientId,
  int recentLimit = 5,
}) {
  const supportedActions = {'taken', 'skipped', 'missed', 'snoozed'};
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
  final eventIds = <(String, String)>{};
  final events = <(String, String, String, int, int?)>{};
  final uniqueActions = <MedicationAction>[];
  for (final action in sorted) {
    final duplicateId =
        action.id.trim().isNotEmpty &&
        !eventIds.add((action.patientId, action.id));
    final duplicateEvent = !events.add((
      action.patientId,
      action.medicationId,
      action.action,
      action.timestamp,
      action.snoozedUntil,
    ));
    if (!duplicateId && !duplicateEvent) uniqueActions.add(action);
  }
  return uniqueActions.take(recentLimit).toList();
}
