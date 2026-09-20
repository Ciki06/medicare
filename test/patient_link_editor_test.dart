import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/widgets/patient_link_editor.dart';
import 'package:medicare/models/user_model.dart';
import 'package:medicare/models/user_role.dart';

void main() {
  testWidgets('patient is previewed before adding and can be removed', (
    tester,
  ) async {
    var emails = <String>[];
    var searches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => PatientLinkEditor(
                emails: emails,
                onChanged: (v) => setState(() => emails = v),
                findPatient: (email) async {
                  searches++;
                  return UserModel(
                    uid: 'p',
                    name: 'Patient One',
                    email: email,
                    role: UserRole.patient,
                    createdAt: DateTime(2026),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add patient'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'PATIENT@example.com');
    await tester.tap(find.text('Find patient'));
    await tester.pumpAndSettle();
    expect(find.text('Patient One'), findsOneWidget);
    expect(emails, isEmpty);
    await tester.tap(find.text('Add to circle'));
    await tester.pumpAndSettle();
    expect(emails, ['patient@example.com']);
    await tester.tap(find.text('Add patient'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'patient@example.com');
    await tester.tap(find.text('Find patient'));
    await tester.pumpAndSettle();
    expect(
      find.text('This patient is already in your circle.'),
      findsOneWidget,
    );
    expect(searches, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove patient@example.com'));
    await tester.pumpAndSettle();
    expect(emails, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
