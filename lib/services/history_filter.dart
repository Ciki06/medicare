import '../models/medication_action.dart';

/// Calendar dates are inclusive, including the entire final day.
bool withinDates(DateTime value, DateTime? start, DateTime? end) {
  final day = DateTime(value.year, value.month, value.day);
  return (start == null ||
          !day.isBefore(DateTime(start.year, start.month, start.day))) &&
      (end == null || !day.isAfter(DateTime(end.year, end.month, end.day)));
}

String medicationStatus(String action) =>
    action == 'skipped' ? 'missed' : action;

List<MedicationAction> filterMedicationActions(
  Iterable<MedicationAction> actions, {
  String? patientId,
  String? status,
  String name = '',
  DateTime? start,
  DateTime? end,
  Set<DateTime>? months,
}) =>
    actions
        .where(
          (a) =>
              (months == null ||
                  months.contains(
                    DateTime(
                      DateTime.fromMillisecondsSinceEpoch(a.timestamp).year,
                      DateTime.fromMillisecondsSinceEpoch(a.timestamp).month,
                    ),
                  )) &&
              (patientId == null || a.patientId == patientId) &&
              (status == null || medicationStatus(a.action) == status) &&
              a.medicationName.toLowerCase().contains(
                name.trim().toLowerCase(),
              ) &&
              withinDates(
                DateTime.fromMillisecondsSinceEpoch(a.timestamp),
                start,
                end,
              ),
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

({int taken, int missed, int snoozed}) medicationTotals(
  Iterable<MedicationAction> actions,
) => (
  taken: actions.where((a) => medicationStatus(a.action) == 'taken').length,
  missed: actions.where((a) => medicationStatus(a.action) == 'missed').length,
  snoozed: actions.where((a) => medicationStatus(a.action) == 'snoozed').length,
);

String shortDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

const reportMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String selectedMonthsLabel(Set<DateTime> months) {
  final sorted = months.toList()..sort();
  return sorted
      .map((d) => '${reportMonthNames[d.month - 1]} ${d.year}')
      .join(', ');
}
