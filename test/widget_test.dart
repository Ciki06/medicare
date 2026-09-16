import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/medication_model.dart';
import 'package:medicare/models/user_model.dart';
import 'package:medicare/models/user_role.dart';
import 'package:medicare/widgets/completed_appointments_section.dart';

void main() {
  testWidgets('completed appointments combine type and location filters', (
    tester,
  ) async {
    final patient = UserModel(
      uid: 'p',
      name: 'Patient',
      email: 'p@example.invalid',
      role: UserRole.patient,
      createdAt: DateTime(2026),
    );
    Appointment appointment(
      String id,
      String title,
      String location, {
      String status = 'completed',
    }) => Appointment(
      id: id,
      title: title,
      location: location,
      status: status,
      date: '2026-09-14',
      time: '09:00',
      patientId: 'p',
      patientName: 'Patient',
      caregiverId: 'c',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompletedAppointmentsSection(
              patients: [patient],
              appointments: [
                appointment('1', 'Dental check', 'North clinic'),
                appointment('2', 'Dental review', 'South clinic'),
                appointment('3', 'Eye exam', 'North clinic'),
                appointment(
                  '4',
                  'Future dental',
                  'North clinic',
                  status: 'scheduled',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Future dental'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Filter completed appointments'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'DENTAL');
    await tester.pump();
    expect(find.text('Eye exam'), findsNothing);
    expect(find.text('Dental check'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), 'north');
    await tester.pump();
    expect(find.text('Dental review'), findsNothing);
    expect(find.text('Dental check'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), 'unknown');
    await tester.pump();
    expect(
      find.text('No completed appointments match these filters.'),
      findsOneWidget,
    );
  });
}
