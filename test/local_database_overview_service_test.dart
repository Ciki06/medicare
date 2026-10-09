import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/services/caregiver_sqlite_service.dart';
import 'package:medicare/services/local_database_overview_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'caregiver_sqlite_service_test.dart' show profile;
import 'patient_sqlite_service_test.dart' show patientProfile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late CaregiverSqliteService database;
  late LocalDatabaseOverviewService service;
  String? uid;
  setUp(() {
    uid = 'viewer';
    database = CaregiverSqliteService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    service = LocalDatabaseOverviewService(
      database: database,
      currentUid: () => uid,
    );
  });
  tearDown(() => database.close());

  test(
    'empty database exposes every application table and its schema',
    () async {
      final overview = await service.load('viewer');
      expect(overview.version, 2);
      expect(overview.recordCount, 0);
      expect(overview.tables.map((table) => table.name), [
        'caregivers',
        'patients',
        'patient_medical_history',
      ]);
      final patients = overview.tables[1];
      expect(patients.columns.first.primaryKey, isTrue);
      expect(patients.columns.first.name, 'patient_id');
      expect(
        patients.columns
            .singleWhere((column) => column.name == 'uid')
            .requiredValue,
        isTrue,
      );
      expect(patients.columns.last.references, 'caregivers.caregiver_id');
      expect(overview.tables.last.columns[1].references, 'patients.patient_id');
      expect(
        overview.tables
            .expand((table) => table.columns)
            .any((column) => column.name == 'password'),
        isFalse,
      );
    },
  );

  test(
    'signed-in viewer sees all accounts and medical history without changing records',
    () async {
      await database.saveCaregiver(
        profile(),
        authenticatedUid: 'caregiver-uid',
      );
      await database.savePatient(
        'patient-uid',
        patientProfile(),
        authenticatedUid: 'patient-uid',
      );
      await database.savePatient('another-patient', {
        ...patientProfile(uid: 'another-patient'),
        'name': 'Another patient',
        'medicalHistory': ['Asthma'],
      }, authenticatedUid: 'another-patient');
      final db = await database.database;
      final before = await db.rawQuery(
        'SELECT * FROM patients ORDER BY patient_id',
      );
      final overview = await service.load('viewer');
      expect(overview.recordCount, 6);
      expect(overview.tables[0].rows.single['firebase_uid'], 'caregiver-uid');
      expect(overview.tables[1].rows.map((row) => row['uid']), [
        'patient-uid',
        'another-patient',
      ]);
      expect(
        overview.tables[2].rows.map((row) => row['medical_history']).toSet(),
        {'Diabetes', 'Hypertension', 'Asthma'},
      );
      expect(
        await db.rawQuery('SELECT * FROM patients ORDER BY patient_id'),
        before,
      );
      expect(await db.getVersion(), 2);
    },
  );

  test('database discovery excludes SQLite and Android bookkeeping', () async {
    final db = await database.database;
    await db.execute('CREATE TABLE android_metadata (locale TEXT)');
    final overview = await service.load('viewer');
    expect(overview.tables.length, 3);
  });

  test(
    'new application tables and quoted names can be inspected safely',
    () async {
      final db = await database.database;
      await db.execute(
        'CREATE TABLE "test""table" (id INTEGER PRIMARY KEY, value TEXT)',
      );
      await db.rawInsert('INSERT INTO "test""table" VALUES (?, ?)', [
        1,
        'Example',
      ]);
      final overview = await service.load('viewer');
      expect(overview.tables.last.name, 'test"table');
      expect(overview.tables.last.rows.single['value'], 'Example');
    },
  );

  test(
    'signed-out, different and empty accounts cannot read records',
    () async {
      uid = null;
      await expectLater(service.load('viewer'), throwsStateError);
      uid = 'other';
      await expectLater(service.load('viewer'), throwsStateError);
      uid = '';
      await expectLater(service.load(''), throwsStateError);
    },
  );

  test('account change during a read rejects its result', () async {
    int checks = 0;
    service = LocalDatabaseOverviewService(
      database: database,
      currentUid: () => ++checks < 3 ? 'viewer' : 'other',
    );
    await expectLater(service.load('viewer'), throwsStateError);
    expect(checks, 3);
  });

  test('snapshots cannot be mutated by the viewer', () async {
    await database.saveCaregiver(profile(), authenticatedUid: 'caregiver-uid');
    final overview = await service.load('viewer');
    expect(() => overview.tables.clear(), throwsUnsupportedError);
    expect(
      () => overview.tables.first.rows.single['name'] = 'Changed',
      throwsUnsupportedError,
    );
    expect(() => overview.tables.first.columns.clear(), throwsUnsupportedError);
  });
}
