import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/screens/home/local_database_overview_page.dart';
import 'package:medicare/services/local_database_overview_service.dart';
import 'package:medicare/theme/app_theme.dart';
import 'package:medicare/widgets/app_header.dart';

LocalDatabaseOverview snapshot({bool empty = false}) => LocalDatabaseOverview(
  version: 2,
  tables: [
    LocalDatabaseTable(
      name: 'caregivers',
      columns: const [
        LocalDatabaseColumn(
          name: 'caregiver_id',
          type: 'INTEGER',
          primaryKey: true,
          requiredValue: true,
        ),
        LocalDatabaseColumn(
          name: 'name',
          type: 'TEXT',
          primaryKey: false,
          requiredValue: true,
        ),
        LocalDatabaseColumn(
          name: 'firebase_uid',
          type: 'TEXT',
          primaryKey: false,
          requiredValue: true,
        ),
        LocalDatabaseColumn(
          name: 'phone',
          type: 'TEXT',
          primaryKey: false,
          requiredValue: false,
        ),
        LocalDatabaseColumn(
          name: 'created_at',
          type: 'TEXT',
          primaryKey: false,
          requiredValue: true,
        ),
      ],
      rows: empty
          ? []
          : [
              {
                'caregiver_id': 1,
                'name': 'Caregiver One',
                'firebase_uid': 'cg-one',
                'phone': null,
                'created_at': '2026-10-09T12:30:00Z',
              },
              {
                'caregiver_id': 2,
                'name': 'Caregiver Two',
                'firebase_uid': 'cg-two',
                'phone': '012345',
              },
            ],
    ),
    LocalDatabaseTable(
      name: 'patients',
      columns: const [
        LocalDatabaseColumn(
          name: 'patient_id',
          type: 'INTEGER',
          primaryKey: true,
          requiredValue: true,
        ),
        LocalDatabaseColumn(
          name: 'name',
          type: 'TEXT',
          primaryKey: false,
          requiredValue: false,
        ),
      ],
      rows: empty
          ? []
          : [
              {'patient_id': 42, 'name': 'Patient One'},
            ],
    ),
    LocalDatabaseTable(
      name: 'patient_medical_history',
      columns: const [
        LocalDatabaseColumn(
          name: 'history_id',
          type: 'INTEGER',
          primaryKey: true,
          requiredValue: true,
        ),
        LocalDatabaseColumn(
          name: 'patient_id',
          type: 'INTEGER',
          primaryKey: false,
          requiredValue: true,
          references: 'patients.patient_id',
        ),
        LocalDatabaseColumn(
          name: 'medical_history',
          type: 'TEXT',
          primaryKey: false,
          requiredValue: false,
        ),
      ],
      rows: empty
          ? []
          : [
              {
                'history_id': 3,
                'patient_id': 42,
                'medical_history': 'Diabetes',
              },
            ],
    ),
  ],
);

class FakeOverviewService extends LocalDatabaseOverviewService {
  LocalDatabaseOverview data = snapshot();
  int loads = 0;
  bool fail = false;
  Completer<LocalDatabaseOverview>? pending;
  final sessions = StreamController<String?>.broadcast();
  @override
  Stream<String?> get uidChanges => sessions.stream;
  @override
  Future<LocalDatabaseOverview> load(String uid) async {
    expect(uid, 'viewer');
    loads++;
    if (fail) throw StateError('Internal secret error');
    return pending == null ? data : await pending!.future;
  }
}

void main() {
  late FakeOverviewService service;
  setUp(() => service = FakeOverviewService());
  tearDown(() => service.sessions.close());
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: LocalDatabaseOverviewPage(
          firebaseUid: 'viewer',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'overview shows every table, counts, read-only status and all accounts',
    (tester) async {
      await open(tester);
      expect(find.text('3 tables'), findsOneWidget);
      expect(find.text('4 records'), findsOneWidget);
      expect(find.text('Read only'), findsOneWidget);
      expect(find.text('Caregivers (2)'), findsOneWidget);
      expect(find.text('Patients (1)'), findsOneWidget);
      expect(find.text('Medical history (1)'), findsOneWidget);
      expect(find.text('Caregiver One'), findsOneWidget);
      expect(find.text('Caregiver Two'), findsOneWidget);
      expect(service.loads, 1);
    },
  );

  testWidgets('expanded record shows readable fields, UID and missing values', (
    tester,
  ) async {
    await open(tester);
    await reveal(tester, find.text('Caregiver One'));
    await tester.tap(find.text('Caregiver One'));
    await tester.pumpAndSettle();
    expect(find.text('cg-one'), findsOneWidget);
    expect(find.text('Firebase UID'), findsOneWidget);
    expect(find.text('Not provided'), findsOneWidget);
    expect(find.textContaining('2026 •'), findsOneWidget);
  });

  testWidgets('a single record uses a clear singular count', (tester) async {
    final original = snapshot();
    service.data = LocalDatabaseOverview(
      version: 2,
      tables: [
        LocalDatabaseTable(
          name: original.tables.first.name,
          columns: original.tables.first.columns,
          rows: [original.tables.first.rows.first],
        ),
      ],
    );
    await open(tester);
    expect(find.text('1 table'), findsOneWidget);
    expect(find.text('1 record'), findsOneWidget);
    expect(find.text('1 of 1 record'), findsOneWidget);
  });

  testWidgets('search filters values and clearing restores rows', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'cg-two');
    await tester.pumpAndSettle();
    expect(find.text('Caregiver One'), findsNothing);
    expect(find.text('Caregiver Two'), findsOneWidget);
    expect(find.text('1 of 2 records'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Caregiver One'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'no-such-record');
    await tester.pumpAndSettle();
    expect(find.textContaining('No records match'), findsOneWidget);
  });

  testWidgets(
    'switching tables shows medical history and relationship fields',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Medical history (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Diabetes'), findsOneWidget);
      expect(find.text('History ID 3 • Patient ID 42'), findsOneWidget);
      await reveal(tester, find.text('Table fields'));
      await tester.tap(find.text('Table fields'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Links to patients.patient_id'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'empty state explains automatic saves and refresh reloads locally',
    (tester) async {
      service.data = snapshot(empty: true);
      await open(tester);
      expect(find.text('0 records'), findsOneWidget);
      expect(
        find.textContaining('saved automatically after account creation'),
        findsOneWidget,
      );
      service.data = snapshot();
      await tester.tap(find.byTooltip('Refresh database'));
      await tester.pumpAndSettle();
      expect(service.loads, 2);
      expect(find.text('4 records'), findsOneWidget);
    },
  );

  testWidgets(
    'errors are readable, expose no internal detail, and can be retried',
    (tester) async {
      service.fail = true;
      await open(tester);
      expect(find.textContaining('Could not read'), findsOneWidget);
      expect(find.textContaining('Internal secret'), findsNothing);
      service.fail = false;
      await tester.tap(find.byTooltip('Refresh database'));
      await tester.pumpAndSettle();
      expect(find.text('4 records'), findsOneWidget);
    },
  );

  testWidgets('sign-out removes records and delayed results cannot reappear', (
    tester,
  ) async {
    await open(tester);
    service.pending = Completer();
    await tester.tap(find.byTooltip('Refresh database'));
    await tester.pump();
    service.sessions.add(null);
    await tester.pumpAndSettle();
    service.pending!.complete(snapshot());
    await tester.pumpAndSettle();
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(find.text('Caregiver One'), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'account switches and auth errors clear already displayed records',
    (tester) async {
      await open(tester);
      expect(find.text('Caregiver One'), findsOneWidget);
      service.sessions.add('another-account');
      await tester.pumpAndSettle();
      expect(find.text('Caregiver One'), findsNothing);
      expect(find.textContaining('Your account changed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(find.text('Caregiver One'), findsOneWidget);
      service.sessions.addError(StateError('Auth stream unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Caregiver One'), findsNothing);
      expect(find.textContaining('Your account changed'), findsOneWidget);
    },
  );

  testWidgets('fits a narrow phone with large text and long names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = snapshot();
    service.data = LocalDatabaseOverview(
      version: original.version,
      tables: [
        LocalDatabaseTable(
          name: original.tables.first.name,
          columns: original.tables.first.columns,
          rows: [
            {
              ...original.tables.first.rows.first,
              'name':
                  'Caregiver with a very long full name that wraps across several lines',
            },
          ],
        ),
        ...original.tables.skip(1),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: child!,
        ),
        home: LocalDatabaseOverviewPage(
          firebaseUid: 'viewer',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(
      tester,
      find.text(
        'Caregiver with a very long full name that wraps across several lines',
      ),
    );
    await tester.tap(
      find.text(
        'Caregiver with a very long full name that wraps across several lines',
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Medical history (1)'));
    await tester.tap(find.text('Medical history (1)'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Table fields'));
    await tester.tap(find.text('Table fields'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('three taps push the overview and Back returns to Profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: AppHeader(
              title: 'Profile',
              onTitleTripleTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LocalDatabaseOverviewPage(
                    firebaseUid: 'viewer',
                    service: service,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Profile'));
    }
    expect(service.loads, 0);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('On this device'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
  });
}
