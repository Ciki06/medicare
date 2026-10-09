import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/services/caregiver_sqlite_service.dart';
import 'package:medicare/services/patient_local_profile_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'patient_sqlite_service_test.dart' show patientProfile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late CaregiverSqliteService database;
  late PatientLocalProfileService service;
  String? uid;
  int reads = 0;
  late Future<Map<String, dynamic>?> Function(String) readProfile;
  setUp(() {
    database = CaregiverSqliteService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    uid = 'patient-uid';
    reads = 0;
    readProfile = (_) async {
      reads++;
      return patientProfile();
    };
    service = PatientLocalProfileService(
      database: database,
      currentUid: () => uid,
      loadProfile: (id) => readProfile(id),
      uidChanges: const Stream.empty(),
    );
  });
  tearDown(() => database.close());
  test('local reads do not fetch Firebase or save automatically', () async {
    expect(await service.load('patient-uid'), isNull);
    expect(reads, 0);
    expect(await (await database.database).query('patients'), isEmpty);
  });
  test(
    'explicit save copies the patient profile and its medical history',
    () async {
      final record = await service.saveCurrentProfile('patient-uid');
      expect(record.uid, uid);
      expect(record.name, 'Patient One');
      expect(record.medicalHistory, hasLength(2));
      expect(reads, 1);
      expect((await service.load('patient-uid'))!.patientId, record.patientId);
      expect(reads, 1);
    },
  );
  test(
    'signed-out and other account sessions cannot view or save patient data',
    () async {
      await service.saveCurrentProfile('patient-uid');
      for (final session in [null, 'another-patient', 'caregiver-uid']) {
        uid = session;
        await expectLater(service.load('patient-uid'), throwsStateError);
        await expectLater(
          service.saveCurrentProfile('patient-uid'),
          throwsStateError,
        );
      }
      expect(reads, 1);
    },
  );
  test(
    'account change during a Firebase read prevents a stale patient save',
    () async {
      final fetch = Completer<Map<String, dynamic>?>();
      readProfile = (_) => fetch.future;
      final saving = service.saveCurrentProfile('patient-uid');
      uid = 'another-patient';
      fetch.complete(patientProfile());
      await expectLater(saving, throwsStateError);
      expect(await database.getPatient('patient-uid'), isNull);
    },
  );
  test(
    'missing, wrong-role, and wrong-UID documents cannot create local data',
    () async {
      for (final data in [
        null,
        {...patientProfile(), 'role': 'caregiver'},
        {...patientProfile(), 'role': 'family'},
        {...patientProfile(), 'role': 'pharmacist'},
        patientProfile(uid: 'wrong-uid'),
      ]) {
        readProfile = (_) async => data;
        await expectLater(
          service.saveCurrentProfile('patient-uid'),
          throwsStateError,
        );
      }
      expect(await database.getPatient('patient-uid'), isNull);
    },
  );
  test(
    'failed server read preserves both the local patient and medical history',
    () async {
      final first = await service.saveCurrentProfile('patient-uid');
      readProfile = (_) async => throw StateError('Server unavailable');
      await expectLater(
        service.saveCurrentProfile('patient-uid'),
        throwsStateError,
      );
      final after = (await database.getPatient('patient-uid'))!;
      expect(after.patientId, first.patientId);
      expect(
        after.medicalHistory.map((entry) => entry.historyId),
        first.medicalHistory.map((entry) => entry.historyId),
      );
    },
  );
  test(
    'sparse server profiles are handled without requiring unrelated model fields',
    () async {
      readProfile = (_) async => {'role': 'patient', 'name': null};
      final saved = await service.saveCurrentProfile('patient-uid');
      expect(saved.uid, 'patient-uid');
      expect(saved.name, isNull);
      expect(saved.medicalHistory, isEmpty);
    },
  );
}
