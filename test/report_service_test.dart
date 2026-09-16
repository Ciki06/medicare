import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/medication_action.dart';
import 'package:medicare/models/user_model.dart';
import 'package:medicare/models/user_role.dart';
import 'package:medicare/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
