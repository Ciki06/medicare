import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/local_patient_record.dart';
import 'package:medicare/screens/home/patient_local_database_page.dart';
import 'package:medicare/services/patient_local_profile_service.dart';
import 'package:medicare/theme/app_theme.dart';

LocalPatientRecord record({String name = 'Local Patient'}) =>
    LocalPatientRecord(
      patientId: 42,
      uid: 'patient-uid',
      name: name,
      icNumber: '501009-01-1234',
      gender: 'Female',
      dateOfBirth: '09/10/1950',
      phone: '0123456789',
      email: 'patient@example.invalid',
      address: 'Room 12',
      caregiverId: 9,
      medicalHistory: [
        LocalPatientMedicalHistory(
          historyId: 1,
          patientId: 42,
          medicalHistory: 'Diabetes',
          createdAt: DateTime.utc(2026, 10, 9),
        ),
      ],
    );

class FakePatientService extends PatientLocalProfileService {
  LocalPatientRecord? local;
  int loads = 0;
  int saves = 0;
  bool failSave = false;
  Object? loadError;
  Completer<LocalPatientRecord?>? pendingLoad;
  final sessions = StreamController<String?>.broadcast();
  @override
  Stream<String?> get uidChanges => sessions.stream;
  @override
  Future<LocalPatientRecord?> load(String uid) async {
    expect(uid, 'patient-uid');
    loads++;
    if (loadError != null) throw loadError!;
    return pendingLoad != null ? await pendingLoad!.future : local;
  }

  @override
  Future<LocalPatientRecord> saveCurrentProfile(String uid) async {
    expect(uid, 'patient-uid');
    saves++;
    if (failSave) throw StateError('Server unavailable');
    return local = record(name: 'Current Firebase Patient');
  }
}

void main() {
  late FakePatientService service;
  setUp(() => service = FakePatientService());
  tearDown(() => service.sessions.close());
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: PatientLocalDatabasePage(
          firebaseUid: 'patient-uid',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'opening shows a clear empty state without saving or fetching Firebase',
    (tester) async {
      await open(tester);
      expect(
        find.textContaining('No local patient record yet.'),
        findsOneWidget,
      );
      expect(service.loads, 1);
      expect(service.saves, 0);
    },
  );
  testWidgets('the complete SQL record and medical history are displayed', (
    tester,
  ) async {
    service.local = record();
    await open(tester);
    for (final value in [
      '42',
      'patient-uid',
      'Local Patient',
      '501009-01-1234',
      'Female',
      '09/10/1950',
      '0123456789',
      'patient@example.invalid',
      'Room 12',
      '9',
      'Diabetes',
      service.local!.age.toString(),
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('Medical History'), findsOneWidget);
    expect(find.textContaining('Saved locally:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('refresh reads local SQLite and never invokes save', (
    tester,
  ) async {
    service.local = record();
    await open(tester);
    service.local = record(name: 'Refreshed Patient');
    await tester.tap(find.byTooltip('Refresh local record'));
    await tester.pumpAndSettle();
    expect(find.text('Refreshed Patient'), findsOneWidget);
    expect(service.loads, 2);
    expect(service.saves, 0);
  });
  testWidgets('explicit save creates and displays the patient profile', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Save current profile locally'));
    await tester.pumpAndSettle();
    expect(service.saves, 1);
    expect(find.text('Current Firebase Patient'), findsOneWidget);
    expect(find.text('Diabetes'), findsOneWidget);
    expect(find.text('Patient profile saved locally.'), findsOneWidget);
  });
  testWidgets(
    'save failure retains the existing local profile and medical history',
    (tester) async {
      service.local = record();
      service.failSave = true;
      await open(tester);
      await tester.ensureVisible(find.text('Save current profile locally'));
      await tester.tap(find.text('Save current profile locally'));
      await tester.pumpAndSettle();
      expect(find.text('Local Patient'), findsOneWidget);
      expect(find.text('Diabetes'), findsOneWidget);
      expect(find.textContaining('Could not save'), findsOneWidget);
    },
  );
  testWidgets(
    'missing optional fields, empty history, and narrow displays are safe',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      service.local = const LocalPatientRecord(
        patientId: 1,
        uid: 'patient-uid',
      );
      await open(tester);
      expect(find.text('Not provided'), findsNWidgets(8));
      expect(find.text('Not linked on this device'), findsOneWidget);
      expect(find.text('No medical history saved locally.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account change clears IC number and medical history and disables actions',
    (tester) async {
      service.local = record();
      await open(tester);
      service.sessions.add('another-uid');
      await tester.pumpAndSettle();
      for (final value in ['Local Patient', '501009-01-1234', 'Diabetes']) {
        expect(find.text(value), findsNothing);
      }
      expect(find.textContaining('Sign in as this patient'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
    },
  );
  testWidgets('session verification errors hide any sensitive local data', (
    tester,
  ) async {
    service.local = record();
    await open(tester);
    service.sessions.addError(StateError('Auth unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Diabetes'), findsNothing);
    expect(find.textContaining('Sign in as this patient'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a delayed local result cannot reappear after sign-out', (
    tester,
  ) async {
    service.pendingLoad = Completer<LocalPatientRecord?>();
    await tester.pumpWidget(
      MaterialApp(
        home: PatientLocalDatabasePage(
          firebaseUid: 'patient-uid',
          service: service,
        ),
      ),
    );
    service.sessions.add(null);
    await tester.pump();
    service.pendingLoad!.complete(record());
    await tester.pumpAndSettle();
    expect(find.text('Diabetes'), findsNothing);
    expect(find.text('501009-01-1234'), findsNothing);
    expect(find.textContaining('Sign in as this patient'), findsOneWidget);
  });
  testWidgets(
    'load failures and unsupported platforms display useful feedback',
    (tester) async {
      service.loadError = UnsupportedError('platform');
      await open(tester);
      expect(find.textContaining('Android and iOS'), findsOneWidget);
      service.loadError = StateError('failure');
      await tester.tap(find.byTooltip('Refresh local record'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load'), findsOneWidget);
    },
  );
}
