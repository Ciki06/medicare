import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/local_caregiver_record.dart';
import 'package:medicare/screens/home/caregiver_local_database_page.dart';
import 'package:medicare/services/caregiver_local_profile_service.dart';
import 'package:medicare/theme/app_theme.dart';

LocalCaregiverRecord record({String name = 'Local Caregiver'}) =>
    LocalCaregiverRecord(
      caregiverId: 42,
      firebaseUid: 'caregiver-uid',
      name: name,
      email: 'local@example.invalid',
      phone: '0123456789',
      profilePicUrl: 'https://example.invalid/avatar.jpg',
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 8),
    );

class FakeProfileService extends CaregiverLocalProfileService {
  LocalCaregiverRecord? local;
  int loads = 0;
  int saves = 0;
  Object? loadError;
  bool failSave = false;
  final sessions = StreamController<String?>.broadcast();
  @override
  Stream<String?> get uidChanges => sessions.stream;
  @override
  Future<LocalCaregiverRecord?> load(String uid) async {
    expect(uid, 'caregiver-uid');
    loads++;
    if (loadError != null) throw loadError!;
    return local;
  }

  @override
  Future<LocalCaregiverRecord> saveCurrentProfile(String uid) async {
    expect(uid, 'caregiver-uid');
    saves++;
    if (failSave) throw StateError('Firebase unavailable');
    return local = record(name: 'Current Firebase Caregiver');
  }
}

void main() {
  late FakeProfileService service;
  setUp(() => service = FakeProfileService());
  tearDown(() => service.sessions.close());
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: CaregiverLocalDatabasePage(
          firebaseUid: 'caregiver-uid',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty state loads SQLite without saving', (tester) async {
    await open(tester);
    expect(
      find.textContaining('No local caregiver record yet.'),
      findsOneWidget,
    );
    expect(service.loads, 1);
    expect(service.saves, 0);
  });
  testWidgets('all available local fields are displayed', (tester) async {
    service.local = record();
    await open(tester);
    for (final value in [
      '42',
      'caregiver-uid',
      'Local Caregiver',
      'local@example.invalid',
      '0123456789',
      'https://example.invalid/avatar.jpg',
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('Local record created'), findsOneWidget);
    expect(find.text('Last local update'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('refresh reloads the local record without a Firebase save', (
    tester,
  ) async {
    service.local = record();
    await open(tester);
    service.local = record(name: 'Refreshed Local Name');
    await tester.tap(find.byTooltip('Refresh local record'));
    await tester.pumpAndSettle();
    expect(find.text('Refreshed Local Name'), findsOneWidget);
    expect(service.loads, 2);
    expect(service.saves, 0);
  });
  testWidgets(
    'explicit save creates and displays the current Firebase profile',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Save current profile locally'));
      await tester.pumpAndSettle();
      expect(service.saves, 1);
      expect(find.text('Current Firebase Caregiver'), findsOneWidget);
      expect(find.text('Caregiver profile saved locally.'), findsOneWidget);
    },
  );
  testWidgets('save failure keeps the previous local record visible', (
    tester,
  ) async {
    service.local = record();
    service.failSave = true;
    await open(tester);
    await tester.ensureVisible(find.text('Save current profile locally'));
    await tester.tap(find.text('Save current profile locally'));
    await tester.pumpAndSettle();
    expect(find.text('Local Caregiver'), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('load errors and unsupported browsers have clear feedback', (
    tester,
  ) async {
    service.loadError = UnsupportedError('web');
    await open(tester);
    expect(find.textContaining('Android and iOS apps'), findsOneWidget);
    service.loadError = StateError('failed');
    await tester.tap(find.byTooltip('Refresh local record'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load'), findsOneWidget);
  });
  testWidgets(
    'account change clears the displayed record and disables actions',
    (tester) async {
      service.local = record();
      await open(tester);
      service.sessions.add('another-uid');
      await tester.pumpAndSettle();
      expect(find.text('Local Caregiver'), findsNothing);
      expect(find.textContaining('Sign in as this caregiver'), findsOneWidget);
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
  testWidgets('missing optional fields and narrow displays remain usable', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    service.local = LocalCaregiverRecord(
      caregiverId: 1,
      firebaseUid: 'caregiver-uid',
      name: 'Caregiver',
      email: 'cg@example.invalid',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await open(tester);
    expect(find.text('Not provided'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
