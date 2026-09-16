import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/user_model.dart';
import 'package:medicare/models/user_role.dart';
import 'package:medicare/widgets/medication_activity_filter.dart';

void main() {
  testWidgets(
    'homepage medication filters collapse and report remains accessible',
    (tester) async {
      final patient = UserModel(
        uid: 'p',
        name: 'Pat',
        email: 'p@example.invalid',
        role: UserRole.patient,
        createdAt: DateTime(2026),
      );
      MedicationActivityCriteria? criteria;
      var reports = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MedicationActivityFilter(
                patients: [patient],
                onChanged: (v) => criteria = v,
                onReport: () => reports++,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Weekly / monthly report'));
      expect(reports, 1);
      await tester.tap(find.byTooltip('Filter medication activity'));
      await tester.pump();
      expect(find.byTooltip('Filter medication activity'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Aspirin');
      expect(criteria?.name, 'Aspirin');
      await tester.tap(find.byTooltip('Close medication filters'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Filter medication activity'));
      await tester.pump();
      expect(find.text('Aspirin'), findsOneWidget);
    },
  );
}
