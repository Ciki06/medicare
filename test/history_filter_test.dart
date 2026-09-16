import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/medication_action.dart';
import 'package:medicare/services/history_filter.dart';
import 'package:medicare/services/notification_identity.dart';

MedicationAction action(
  String id,
  String patient,
  String status,
  DateTime date, {
  String name = 'Medicine A',
}) => MedicationAction(
  id: id,
  medicationId: 'med',
  medicationName: name,
  patientId: patient,
  action: status,
  timestamp: date.millisecondsSinceEpoch,
);

void main() {
  test(
    'combined filters include the entire end date and normalize skipped as missed',
    () {
      final rows = [
        action('yes', 'p1', 'skipped', DateTime(2026, 9, 14, 23, 59)),
        action('next', 'p1', 'skipped', DateTime(2026, 9, 15)),
        action('other patient', 'p2', 'skipped', DateTime(2026, 9, 14)),
        action('other status', 'p1', 'taken', DateTime(2026, 9, 14)),
        action(
          'other drug',
          'p1',
          'skipped',
          DateTime(2026, 9, 14),
          name: 'Different',
        ),
      ];
      expect(
        filterMedicationActions(
          rows,
          patientId: 'p1',
          status: 'missed',
          name: ' MEDICINE ',
          start: DateTime(2026, 9, 14),
          end: DateTime(2026, 9, 14),
        ).map((a) => a.id),
        ['yes'],
      );
    },
  );
  test(
    'totals count recorded events without treating snoozes as missed doses',
    () {
      final rows = [
        'taken',
        'skipped',
        'missed',
        'snoozed',
        'snoozed',
        'unknown',
      ].map((s) => action(s, 'p1', s, DateTime(2026, 9, 14)));
      expect(medicationTotals(rows), (taken: 1, missed: 2, snoozed: 2));
      expect(medicationTotals([]), (taken: 0, missed: 0, snoozed: 0));
    },
  );
  test('calendar range handles leap day and month boundaries', () {
    expect(
      withinDates(
        DateTime(2024, 2, 29, 23, 59),
        DateTime(2024, 2),
        DateTime(2024, 2, 29),
      ),
      true,
    );
    expect(
      withinDates(DateTime(2024, 3), DateTime(2024, 2), DateTime(2024, 2, 29)),
      false,
    );
  });
  test('notification identity is stable and separates alerts', () {
    expect(notificationId('sos:alert-a'), notificationId('sos:alert-a'));
    expect(notificationId('sos:alert-a'), isNot(notificationId('sos:alert-b')));
    expect(notificationId('sos:alert-a'), inInclusiveRange(0, 0x7fffffff));
  });
}
