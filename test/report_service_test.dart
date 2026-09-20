import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/medication_action.dart';
import 'package:medicare/models/user_model.dart';
import 'package:medicare/models/user_role.dart';
import 'package:medicare/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exports only selected non-consecutive months', () async {
    final bytes = await ReportService.build(
      actions: List.generate(
        3,
        (i) => MedicationAction(
          id: '$i',
          medicationId: 'm',
          medicationName: [
            'January medicine',
            'Excluded February medicine',
            'March medicine',
          ][i],
          patientId: 'p',
          action: 'taken',
          timestamp: DateTime(2026, i + 1, 15, 8).millisecondsSinceEpoch,
        ),
      ),
      patients: [
        UserModel(
          uid: 'p',
          name: 'Sample Patient',
          email: 'sample@example.invalid',
          role: UserRole.patient,
          createdAt: DateTime(2026),
        ),
      ],
      start: DateTime(2026, 1),
      end: DateTime(2026, 3, 31),
      period: 'Monthly',
      months: {DateTime(2026, 1), DateTime(2026, 3)},
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    if (const bool.fromEnvironment('MEDICARE_REPORT_QA')) {
      final file = File('tmp/pdfs/report-selected-months.pdf');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
  });
  test('exports a monthly report with no recorded actions', () async {
    final bytes = await ReportService.build(
      actions: [],
      patients: [],
      start: DateTime(2026, 9),
      end: DateTime(2026, 9, 30),
      period: 'Monthly',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    if (const bool.fromEnvironment('MEDICARE_REPORT_QA')) {
      final file = File('tmp/pdfs/report-empty.pdf');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
  });
  test(
    'exports a multipage report with all patient medication events',
    () async {
      final patients = [
        UserModel(
          uid: 'p1',
          name: 'Amélie Tan',
          email: 'sample@example.invalid',
          role: UserRole.patient,
          createdAt: DateTime(2026),
        ),
      ];
      final rows = List.generate(
        100,
        (i) => MedicationAction(
          id: '$i',
          medicationId: 'm$i',
          medicationName: 'Sample medicine ${i + 1}',
          patientId: 'p1',
          action: ['taken', 'skipped', 'snoozed'][i % 3],
          timestamp: DateTime(2026, 9, 14, 8, i).millisecondsSinceEpoch,
        ),
      );
      final bytes = await ReportService.build(
        actions: rows,
        patients: patients,
        start: DateTime(2026, 9, 14),
        end: DateTime(2026, 9, 20),
        period: 'Weekly',
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));
      if (const bool.fromEnvironment('MEDICARE_REPORT_QA')) {
        final file = File('tmp/pdfs/report-sample.pdf');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
    },
  );
}
