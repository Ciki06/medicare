import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/local_patient_record.dart';
import 'package:medicare/models/medication_model.dart';
import 'package:medicare/services/caregiver_sqlite_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'caregiver_sqlite_service_test.dart' show profile;

Map<String, dynamic> patientProfile({String uid = 'patient-uid'}) => {
  'uid': uid,
  'role': 'patient',
  'name': 'Patient One',
  'email': 'patient@example.invalid',
  'icNumber': '501009-01-1234',
  'gender': 'Female',
  'dateOfBirth': '09/10/1950',
  'phone': '0123456789',
  'address': 'Room 12',
  'caregiverId': 'caregiver-uid',
  'medicalHistory': ['Diabetes', 'Hypertension'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late CaregiverSqliteService service;
  setUp(
    () => service = CaregiverSqliteService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    ),
  );
  tearDown(() => service.close());

  Future<LocalPatientRecord> save(
    Map<String, dynamic> data, {
    String uid = 'patient-uid',
  }) => service.savePatient(uid, data, authenticatedUid: uid);

  Medication cachedMedication({
    String id = 'medication-1',
    String patientUid = 'patient-uid',
    String name = 'Daily medicine',
    int stock = 12,
  }) => Medication(
    id: id,
    name: name,
    dosage: '1 tablet',
    time: '08:30',
    days: const ['Monday', 'Wednesday'],
    patientId: patientUid,
    patientName: 'Patient One',
    caregiverId: 'caregiver-uid',
    type: 'Pill',
    currentStock: stock,
    imageUrl: 'https://example.invalid/medicine.png',
    remindRefill: true,
    remindThreshold: 4,
    startDate: '2026-10-01',
    intervalDays: 2,
    timeZone: 'Asia/Kuala_Lumpur',
  );

  Appointment cachedAppointment({
    String id = 'appointment-1',
    String patientUid = 'patient-uid',
    String title = 'Clinic visit',
    String status = 'scheduled',
    int remindBefore = 15,
  }) => Appointment(
    id: id,
    title: title,
    date: '2026-10-10',
    time: '09:30',
    location: 'Clinic A',
    patientId: patientUid,
    patientName: 'Patient One',
    caregiverId: 'caregiver-uid',
    status: status,
    remindBefore: remindBefore,
  );

  test(
    'version 8 creates the shared schedule caches and account tables',
    () async {
      final db = await service.database;
      expect(await db.getVersion(), 8);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
      );
      expect(tables.map((row) => row['name']).toSet(), {
        'caregivers',
        'patients',
        'patient_medical_history',
        'family_members',
        'patient_family_links',
        'pharmacists',
        'patient_medication_cache',
        'patient_appointment_cache',
      });
      expect(
        (await db.rawQuery(
          'PRAGMA table_info(family_members)',
        )).map((row) => row['name']),
        ['family_id', 'uid', 'name', 'relationship', 'phone', 'email'],
      );
      expect(
        (await db.rawQuery(
          'PRAGMA table_info(pharmacists)',
        )).map((row) => row['name']),
        ['pharmacy_id', 'uid', 'name', 'phone', 'email'],
      );
      expect(
        (await db.rawQuery(
          'PRAGMA table_info(patient_medication_cache)',
        )).map((row) => row['name']),
        [
          'medication_id',
          'patient_id',
          'caregiver_id',
          'current_stock',
          'days_json',
          'dosage',
          'image_url',
          'interval_days',
          'name',
          'patient_name',
          'remind_refill',
          'remind_threshold',
          'start_date',
          'time',
          'timezone',
          'type',
        ],
      );
      final patientColumns = await db.rawQuery('PRAGMA table_info(patients)');
      expect(patientColumns.map((row) => row['name']), [
        'patient_id',
        'uid',
        'name',
        'ic_number',
        'gender',
        'date_of_birth',
        'phone',
        'email',
        'address',
        'caregiver_id',
      ]);
      expect(patientColumns.first['pk'], 1);
      expect(
        patientColumns.singleWhere((row) => row['name'] == 'uid')['notnull'],
        1,
      );
      final historyColumns = await db.rawQuery(
        'PRAGMA table_info(patient_medical_history)',
      );
      expect(historyColumns.map((row) => row['name']), [
        'history_id',
        'patient_id',
        'medical_history',
        'created_at',
      ]);
      expect(historyColumns.first['pk'], 1);
      expect(
        historyColumns.singleWhere(
          (row) => row['name'] == 'patient_id',
        )['notnull'],
        1,
      );
      expect(
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await db.rawQuery(
          'PRAGMA foreign_key_list(patient_appointment_cache)',
        )).single['table'],
        'patients',
      );
    },
  );

  test(
    'medication cache round trips all schedule fields and updates by document ID',
    () async {
      await save(patientProfile());
      await service.replacePatientMedicationCache('patient-uid', [
        cachedMedication(),
      ]);
      final first = (await service.getCachedPatientMedications(
        'patient-uid',
      )).single;
      expect(first.id, 'medication-1');
      expect(first.days, ['Monday', 'Wednesday']);
      expect(first.currentStock, 12);
      expect(first.intervalDays, 2);
      expect(first.remindRefill, isTrue);
      expect(first.remindThreshold, 4);
      expect(first.startDate, '2026-10-01');
      expect(first.timeZone, 'Asia/Kuala_Lumpur');
      expect(first.toMap()['timeZone'], 'Asia/Kuala_Lumpur');

      await service.replacePatientMedicationCache('patient-uid', [
        cachedMedication(name: 'Updated medicine', stock: 7),
      ]);
      final updated = (await service.getCachedPatientMedications(
        'patient-uid',
      )).single;
      expect(updated.name, 'Updated medicine');
      expect(updated.currentStock, 7);
      expect(
        (await (await service.database).query(
          'patient_medication_cache',
        )).length,
        1,
      );
    },
  );

  test(
    'appointment cache updates by document ID and scopes by local patient',
    () async {
      await save(patientProfile());
      await save(patientProfile(uid: 'another-patient'), uid: 'another-patient');
      await service.replacePatientAppointmentCache('patient-uid', [
        cachedAppointment(),
      ]);
      final first =
          (await service.getCachedPatientAppointments('patient-uid')).single;
      expect(first.id, 'appointment-1');
      expect(first.title, 'Clinic visit');
      expect(first.patientId, 'patient-uid');
      expect(first.remindBefore, 15);

      await service.replacePatientAppointmentCache('patient-uid', [
        cachedAppointment(title: 'Updated clinic visit', status: 'confirmed'),
      ]);
      final updated =
          (await service.getCachedPatientAppointments('patient-uid')).single;
      expect(updated.title, 'Updated clinic visit');
      expect(updated.status, 'confirmed');
      expect(
        await service.getCachedPatientAppointments('another-patient'),
        isEmpty,
      );
      expect(
        await (await service.database).query('patient_appointment_cache'),
        hasLength(1),
      );
    },
  );

  test(
    'missing local patient does not create a row or appointment cache',
    () async {
    await service.replacePatientAppointmentCache('missing-patient', [
      cachedAppointment(patientUid: 'missing-patient'),
    ]);
      expect(
        await service.getCachedPatientAppointments('missing-patient'),
        isEmpty,
      );
      expect(await (await service.database).query('patients'), isEmpty);
      expect(
        await (await service.database).query('patient_appointment_cache'),
        isEmpty,
      );
    },
  );

  test(
    'authoritative empty refresh clears only that patient medication cache',
    () async {
      await save(patientProfile());
      await save(patientProfile(uid: 'another-patient'), uid: 'another-patient');
      await service.replacePatientMedicationCache('patient-uid', [
        cachedMedication(),
      ]);
      await service.replacePatientMedicationCache('another-patient', [
        cachedMedication(id: 'other-medication', patientUid: 'another-patient'),
      ]);
      await service.replacePatientMedicationCache('patient-uid', const []);
      expect(await service.getCachedPatientMedications('patient-uid'), isEmpty);
      expect(
        (await service.getCachedPatientMedications(
          'another-patient',
        )).single.id,
        'other-medication',
      );
    },
  );

  test(
    'a mixed-patient response is rejected without deleting the prior cache',
    () async {
      await save(patientProfile());
      await service.replacePatientMedicationCache('patient-uid', [
        cachedMedication(),
      ]);
      await expectLater(
        service.replacePatientMedicationCache('patient-uid', [
          cachedMedication(),
          cachedMedication(
            id: 'wrong-patient-med',
            patientUid: 'another-patient',
          ),
        ]),
        throwsStateError,
      );
      expect(
        (await service.getCachedPatientMedications('patient-uid')).single.id,
        'medication-1',
      );
    },
  );

  test(
    'insert/read maps all existing Firestore fields and retrieves patient medical history',
    () async {
      expect(await service.getPatient('patient-uid'), isNull);
      final first = await save(patientProfile());
      final loaded = (await service.getPatient('patient-uid'))!;
      expect(loaded.patientId, first.patientId);
      expect(loaded.uid, 'patient-uid');
      expect(loaded.name, 'Patient One');
      expect(loaded.icNumber, '501009-01-1234');
      expect(loaded.gender, 'Female');
      expect(loaded.dateOfBirth, '09/10/1950');
      expect(loaded.phone, '0123456789');
      expect(loaded.email, 'patient@example.invalid');
      expect(loaded.address, 'Room 12');
      expect(loaded.caregiverId, isNull);
      expect(loaded.medicalHistory.map((entry) => entry.medicalHistory), [
        'Diabetes',
        'Hypertension',
      ]);
      expect(
        loaded.medicalHistory.every(
          (entry) =>
              entry.patientId == loaded.patientId && entry.createdAt!.isUtc,
        ),
        isTrue,
      );
      expect(await service.getPatient('another-uid'), isNull);
    },
  );

  test(
    'updates preserve the patient ID and prevent duplicate medical conditions',
    () async {
      final first = await save(patientProfile());
      final second = await save({
        ...patientProfile(),
        'name': 'Updated Patient',
        'medicalHistory': ['Diabetes', 'Diabetes', ' Asthma ', ''],
      });
      expect(second.patientId, first.patientId);
      expect(second.name, 'Updated Patient');
      expect(second.medicalHistory.map((entry) => entry.medicalHistory), [
        'Diabetes',
        'Asthma',
      ]);
      expect(
        second.medicalHistory.first.historyId,
        first.medicalHistory.first.historyId,
      );
      expect(
        second.medicalHistory.first.createdAt,
        first.medicalHistory.first.createdAt,
      );
      expect(await (await service.database).query('patients'), hasLength(1));
    },
  );

  test('SQLite UNIQUE uid constraint rejects direct duplicates', () async {
    await save(patientProfile());
    final db = await service.database;
    final row = Map<String, Object?>.from((await db.query('patients')).single)
      ..remove('patient_id');
    await expectLater(
      db.insert('patients', row),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('patients'), hasLength(1));
  });

  test(
    'concurrent saves safely update one patient and one set of conditions',
    () async {
      final records = await Future.wait(
        List.generate(5, (_) => save(patientProfile())),
      );
      expect(records.map((record) => record.patientId).toSet(), hasLength(1));
      final db = await service.database;
      expect(await db.query('patients'), hasLength(1));
      expect(await db.query('patient_medical_history'), hasLength(2));
    },
  );

  test(
    'null, missing, and blank profile fields never erase previously saved values',
    () async {
      final first = await save(patientProfile());
      final second = await save({
        'uid': 'patient-uid',
        'role': 'patient',
        'name': null,
        'phone': '',
        'dateOfBirth': ' ',
        'medicalHistory': null,
      });
      expect(second.patientId, first.patientId);
      expect(second.name, first.name);
      expect(second.phone, first.phone);
      expect(second.email, first.email);
      expect(second.dateOfBirth, first.dateOfBirth);
      expect(
        second.medicalHistory.map((entry) => entry.historyId),
        first.medicalHistory.map((entry) => entry.historyId),
      );
      final empty = await save({
        'role': 'patient',
        'name': null,
        'phone': null,
      }, uid: 'sparse-uid');
      expect(empty.uid, 'sparse-uid');
      expect(empty.name, isNull);
      expect(empty.phone, isNull);
      expect(empty.medicalHistory, isEmpty);
    },
  );

  test(
    'an explicit empty medical history clears only that patient local conditions',
    () async {
      await save(patientProfile());
      await save(patientProfile(uid: 'other-patient'), uid: 'other-patient');
      final cleared = await save({
        ...patientProfile(),
        'medicalHistory': <String>[],
      });
      expect(cleared.medicalHistory, isEmpty);
      expect(
        (await service.getPatient('other-patient'))!.medicalHistory,
        hasLength(2),
      );
    },
  );

  test(
    'caregiver Firebase UID resolves to a local integer without creating caregiver copies',
    () async {
      final caregiver = await service.saveCaregiver(
        profile(),
        authenticatedUid: 'caregiver-uid',
      );
      final patient = await save(patientProfile());
      expect(patient.caregiverId, caregiver.caregiverId);
      final preserved = await save({'role': 'patient'});
      expect(preserved.caregiverId, caregiver.caregiverId);
      final unlinked = await save({
        ...patientProfile(),
        'caregiverId': 'unknown-caregiver',
      });
      expect(unlinked.caregiverId, isNull);
      expect(await (await service.database).query('caregivers'), hasLength(1));
      await save({...patientProfile(), 'caregiverId': '123'});
      expect((await service.getPatient('patient-uid'))!.caregiverId, isNull);
    },
  );

  test(
    'foreign keys reject orphan medical history and prevent duplicate conditions',
    () async {
      final patient = await save(patientProfile());
      final db = await service.database;
      await expectLater(
        db.insert('patient_medical_history', {
          'patient_id': 9999,
          'medical_history': 'Orphan',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('patient_medical_history', {
          'patient_id': patient.patientId,
          'medical_history': 'Diabetes',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.delete(
        'patients',
        where: 'patient_id = ?',
        whereArgs: [patient.patientId],
      );
      expect(await db.query('patient_medical_history'), isEmpty);
    },
  );

  test(
    'invalid data, other roles, mismatched UIDs and empty UIDs cannot be saved',
    () async {
      for (final bad in [
        {...patientProfile(), 'role': 'caregiver'},
        {...patientProfile(), 'role': 'family'},
        {...patientProfile(), 'role': 'pharmacist'},
        {...patientProfile(), 'uid': 'other-uid'},
      ]) {
        await expectLater(save(bad), throwsStateError);
      }
      await expectLater(
        service.savePatient(
          'patient-uid',
          patientProfile(),
          authenticatedUid: 'other-uid',
        ),
        throwsStateError,
      );
      await expectLater(
        service.savePatient('', {'role': 'patient'}, authenticatedUid: ''),
        throwsStateError,
      );
      await expectLater(service.getPatient(' '), throwsArgumentError);
      for (final bad in [
        {...patientProfile(), 'phone': 123},
        {...patientProfile(), 'caregiverId': 1},
        {
          ...patientProfile(),
          'medicalHistory': ['Valid', null],
        },
        {...patientProfile(), 'medicalHistory': 'Diabetes'},
      ]) {
        await expectLater(save(bad), throwsArgumentError);
      }
      expect(await (await service.database).query('patients'), isEmpty);
    },
  );

  test(
    'profile and medical history update together or roll back together',
    () async {
      final first = await save(patientProfile());
      final db = await service.database;
      await db.execute(
        "CREATE TRIGGER fail_condition BEFORE INSERT ON patient_medical_history WHEN NEW.medical_history = 'Fail' BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        save({
          ...patientProfile(),
          'name': 'Should roll back',
          'medicalHistory': ['Fail'],
        }),
        throwsA(isA<DatabaseException>()),
      );
      final after = (await service.getPatient('patient-uid'))!;
      expect(after.name, first.name);
      expect(
        after.medicalHistory.map((entry) => entry.historyId),
        first.medicalHistory.map((entry) => entry.historyId),
      );
    },
  );

  test(
    'no passwords, tokens, notes, or unrelated profile fields are copied',
    () async {
      await save({
        ...patientProfile(),
        'password': 'secret',
        'token': 'secret',
        'medicalNotes': 'not requested',
        'profilePicUrl': 'https://example.invalid?token=secret',
      });
      final db = await service.database;
      expect(
        (await db.query('patients')).single.values,
        isNot(contains('secret')),
      );
      expect(
        (await db.query('patients')).single.values,
        isNot(contains('not requested')),
      );
    },
  );

  test(
    'version 1 upgrade preserves caregivers and persists both roles after reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'medicare-patient-upgrade-',
      );
      final path = '${directory.path}/medicare_local.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE caregivers (caregiver_id INTEGER PRIMARY KEY AUTOINCREMENT, firebase_uid TEXT NOT NULL UNIQUE, name TEXT NOT NULL, email TEXT NOT NULL, phone TEXT, profile_pic_url TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
            );
            await db.insert('caregivers', {
              'caregiver_id': 9,
              'firebase_uid': 'caregiver-uid',
              'name': 'Existing Caregiver',
              'email': 'cg@example.invalid',
              'phone': '123',
              'created_at': '2026-10-08T00:00:00.000Z',
              'updated_at': '2026-10-08T00:00:00.000Z',
            });
          },
        ),
      );
      await old.close();
      final upgraded = CaregiverSqliteService(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      try {
        final caregiver = (await upgraded.getCaregiver('caregiver-uid'))!;
        expect(caregiver.caregiverId, 9);
        expect(caregiver.name, 'Existing Caregiver');
        final patient = await upgraded.savePatient(
          'patient-uid',
          patientProfile(),
          authenticatedUid: 'patient-uid',
        );
        expect(patient.caregiverId, 9);
        await upgraded.close();
        final reopened = (await upgraded.getPatient('patient-uid'))!;
        expect(reopened.patientId, patient.patientId);
        expect(
          reopened.medicalHistory.map((entry) => entry.historyId),
          patient.medicalHistory.map((entry) => entry.historyId),
        );
        expect(
          (await upgraded.getCaregiver('caregiver-uid'))!.createdAt,
          caregiver.createdAt,
        );
        expect(
          await (await upgraded.database).rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      } finally {
        await upgraded.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'age is derived from date of birth around birthdays and rejects invalid dates',
    () {
      LocalPatientRecord record(String? dob) =>
          LocalPatientRecord(patientId: 1, uid: 'p', dateOfBirth: dob);
      expect(record('09/10/1950').ageAt(DateTime(2026, 10, 8)), 75);
      expect(record('09/10/1950').ageAt(DateTime(2026, 10, 9)), 76);
      expect(record('1950-10-09').ageAt(DateTime(2026, 10, 9)), 76);
      expect(record('29/02/2000').ageAt(DateTime(2026, 3, 1)), 26);
      for (final dob in [
        null,
        '',
        'unknown',
        '31/02/1950',
        '2026-02-30',
        '09/10/2030',
      ]) {
        expect(record(dob).ageAt(DateTime(2026, 10, 9)), isNull);
      }
    },
  );
}
