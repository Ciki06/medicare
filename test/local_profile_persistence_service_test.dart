import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/user_role.dart';
import 'package:medicare/services/caregiver_sqlite_service.dart';
import 'package:medicare/services/local_profile_persistence_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'caregiver_sqlite_service_test.dart' show profile;
import 'patient_sqlite_service_test.dart' show patientProfile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late CaregiverSqliteService database;
  late LocalProfilePersistenceService service;
  String? currentUid;
  Map<String, dynamic>? caregiver;
  setUp(() {
    currentUid = 'patient-uid';
    caregiver = profile().toMap();
    database = CaregiverSqliteService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    service = LocalProfilePersistenceService(
      database: database,
      currentUid: () => currentUid,
      loadCaregiver: (_) async => caregiver,
    );
  });
  tearDown(() => database.close());

  test(
    'automatic patient save includes every field and medical history',
    () async {
      expect(
        await service.saveAuthenticatedProfile('patient-uid', patientProfile()),
        isTrue,
      );
      final saved = (await database.getPatient('patient-uid'))!;
      expect(saved.name, 'Patient One');
      expect(saved.email, 'patient@example.invalid');
      expect(saved.icNumber, '501009-01-1234');
      expect(saved.dateOfBirth, '09/10/1950');
      expect(saved.medicalHistory.map((entry) => entry.medicalHistory), [
        'Diabetes',
        'Hypertension',
      ]);
    },
  );

  test(
    'repeat sign-ins update the same UID without erasing incomplete fields',
    () async {
      await service.saveAuthenticatedProfile('patient-uid', patientProfile());
      final first = (await database.getPatient('patient-uid'))!;
      await service.saveAuthenticatedProfile('patient-uid', {
        'uid': 'patient-uid',
        'role': 'patient',
        'name': 'Updated name',
        'phone': null,
        'address': '',
        'medicalHistory': null,
      });
      final saved = (await database.getPatient('patient-uid'))!;
      expect(saved.patientId, first.patientId);
      expect(saved.name, 'Updated name');
      expect(saved.phone, first.phone);
      expect(saved.address, first.address);
      expect(saved.medicalHistory.length, 2);
      expect((await (await database.database).query('patients')).length, 1);
      await service.saveAuthenticatedProfile('patient-uid', {
        ...patientProfile(),
        'medicalHistory': <String>[],
      });
      expect(
        (await database.getPatient('patient-uid'))!.medicalHistory,
        isEmpty,
      );
    },
  );

  test(
    'caregiver profile automatically upserts and never saves image access tokens',
    () async {
      currentUid = 'caregiver-uid';
      expect(
        await service.saveAuthenticatedProfile(currentUid!, caregiver!),
        isTrue,
      );
      final first = (await database.getCaregiver(currentUid!))!;
      expect(
        await service.saveAuthenticatedProfile(currentUid!, {
          ...caregiver!,
          'name': 'New name',
        }),
        isTrue,
      );
      final saved = (await database.getCaregiver(currentUid!))!;
      expect(saved.caregiverId, first.caregiverId);
      expect(saved.name, 'New name');
      expect(saved.profilePicUrl, 'https://example.invalid/profile.jpg');
      expect((await (await database.database).query('caregivers')).length, 1);
    },
  );

  test(
    'registration saves a new patient and resolves caregiver ID without changing session',
    () async {
      currentUid = 'caregiver-uid';
      expect(
        await service.saveCreatedPatient(
          patientProfile(),
          caregiverUid: currentUid!,
        ),
        isTrue,
      );
      final saved = (await database.getPatient('patient-uid'))!;
      final owner = (await database.getCaregiver('caregiver-uid'))!;
      expect(saved.caregiverId, owner.caregiverId);
      expect(saved.medicalHistory.length, 2);
      expect(currentUid, 'caregiver-uid');
      expect(
        await service.saveCreatedPatient(
          patientProfile(),
          caregiverUid: currentUid!,
        ),
        isTrue,
      );
      expect(
        (await database.getPatient('patient-uid'))!.patientId,
        saved.patientId,
      );
    },
  );

  test(
    'wrong owners, mismatched profile UIDs and unsupported roles cannot write',
    () async {
      expect(
        await service.saveAuthenticatedProfile('another-uid', patientProfile()),
        isFalse,
      );
      expect(
        await service.saveAuthenticatedProfile('patient-uid', {
          ...patientProfile(),
          'uid': 'another-uid',
        }),
        isFalse,
      );
      currentUid = null;
      expect(
        await service.saveAuthenticatedProfile('patient-uid', patientProfile()),
        isFalse,
      );
      currentUid = 'caregiver-uid';
      for (final invalid in [
        {...patientProfile(), 'caregiverId': 'other-caregiver'},
        {...patientProfile(), 'role': 'family'},
        {...patientProfile(), 'uid': ''},
      ]) {
        expect(
          await service.saveCreatedPatient(invalid, caregiverUid: currentUid!),
          isFalse,
        );
      }
      caregiver = {...caregiver!, 'role': 'patient'};
      expect(
        await service.saveCreatedPatient(
          patientProfile(),
          caregiverUid: currentUid!,
        ),
        isFalse,
      );
      caregiver = {...profile().toMap(), 'uid': 'other-caregiver'};
      expect(
        await service.saveCreatedPatient(
          patientProfile(),
          caregiverUid: currentUid!,
        ),
        isFalse,
      );
      expect(await database.getPatient('patient-uid'), isNull);
      expect(await database.getCaregiver('caregiver-uid'), isNull);
    },
  );

  test(
    'Family and Pharmacist roles save only their own role records',
    () async {
      currentUid = 'caregiver-uid';
      final family = {
        'uid': currentUid,
        'role': 'family',
        'name': 'Family',
        'email': 'family@example.invalid',
        'linkedPatientIds': ['missing-patient'],
      };
      expect(
        await service.saveAuthenticatedProfile(currentUid!, family),
        isTrue,
      );
      expect(
        await service.saveAuthenticatedProfile(currentUid!, {
          ...profile(role: UserRole.pharmacist).toMap(),
        }),
        isTrue,
      );
      expect(await (await database.database).query('caregivers'), isEmpty);
      expect(await (await database.database).query('patients'), isEmpty);
      expect((await database.getFamily(currentUid!))!['name'], 'Family');
      expect(
        (await database.getPharmacist(currentUid!))!['name'],
        'Caregiver One',
      );
      expect(
        (await (await database.database).query('patient_family_links')),
        isEmpty,
      );
    },
  );

  test(
    'Pharmacist login upserts by Firebase UID and preserves missing values',
    () async {
      currentUid = 'pharmacist-uid';
      final first = {
        'uid': currentUid,
        'role': 'pharmacist',
        'name': 'Pharmacy One',
        'phone': '0123456789',
        'email': 'pharmacist@example.invalid',
      };
      expect(
        await service.saveAuthenticatedProfile(currentUid!, first),
        isTrue,
      );
      final savedFirst = await database.getPharmacist(currentUid!);
      expect(savedFirst?['name'], 'Pharmacy One');
      expect(
        await service.saveAuthenticatedProfile(currentUid!, {
          'uid': currentUid,
          'role': 'pharmacist',
          'name': 'Pharmacy Updated',
          'phone': null,
          'email': '',
        }),
        isTrue,
      );
      final saved = await database.getPharmacist(currentUid!);
      expect(saved?['pharmacy_id'], savedFirst?['pharmacy_id']);
      expect(saved?['name'], 'Pharmacy Updated');
      expect(saved?['phone'], '0123456789');
      expect(saved?['email'], 'pharmacist@example.invalid');
      expect((await (await database.database).query('pharmacists')).length, 1);
      currentUid = 'family-uid';
      expect(
        await service.saveAuthenticatedProfile(currentUid!, {
          'uid': currentUid,
          'role': 'family',
          'name': 'Not pharmacist',
        }),
        isTrue,
      );
      expect(await database.getPharmacist('family-uid'), isNull);
      expect(
        (await database.getPharmacist('pharmacist-uid'))?['name'],
        'Pharmacy Updated',
      );
    },
  );

  test(
    'family relogin upserts and resolves only existing local patients',
    () async {
      await database.savePatient('patient-local', {
        ...patientProfile(),
        'uid': 'patient-local',
      }, authenticatedUid: 'patient-local');
      final family = {
        'uid': 'patient-uid',
        'role': 'family',
        'name': 'Family One',
        'relationship': 'Daughter',
        'email': 'family@example.invalid',
        'linkedPatientIds': ['patient-local', 'not-downloaded'],
      };
      expect(
        await service.saveAuthenticatedProfile('patient-uid', family),
        isTrue,
      );
      final first = await database.getFamily('patient-uid');
      expect((first!['linked_patients'] as List).length, 1);
      expect(await (await database.database).getVersion(), 8);
      expect(
        await service.saveAuthenticatedProfile('patient-uid', {
          ...family,
          'name': 'Family Two',
        }),
        isTrue,
      );
      final saved = await database.getFamily('patient-uid');
      expect(saved!['family_id'], first['family_id']);
      expect(saved['name'], 'Family Two');
      expect(
        (await (await database.database).query('family_members')).length,
        1,
      );
      expect(
        (await (await database.database).rawQuery(
          'PRAGMA foreign_keys',
        )).single['foreign_keys'],
        1,
      );
    },
  );

  test(
    'session change during caregiver verification prevents a stale write',
    () async {
      currentUid = 'caregiver-uid';
      service = LocalProfilePersistenceService(
        database: database,
        currentUid: () => currentUid,
        loadCaregiver: (_) async {
          currentUid = 'another-uid';
          return caregiver;
        },
      );
      expect(
        await service.saveCreatedPatient(
          patientProfile(),
          caregiverUid: 'caregiver-uid',
        ),
        isFalse,
      );
      expect(await (await database.database).query('patients'), isEmpty);
      expect(await (await database.database).query('caregivers'), isEmpty);
    },
  );

  test(
    'SQLite failures return failure rather than failing Firebase flow',
    () async {
      final db = await database.database;
      await db.execute(
        "CREATE TRIGGER fail_patient BEFORE INSERT ON patients BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      expect(
        await service.saveAuthenticatedProfile('patient-uid', patientProfile()),
        isFalse,
      );
      expect(await database.getPatient('patient-uid'), isNull);
      currentUid = 'caregiver-uid';
      expect(
        await service.saveCreatedPatient(
          patientProfile(),
          caregiverUid: currentUid!,
        ),
        isFalse,
      );
      expect(await database.getPatient('patient-uid'), isNull);
    },
  );

  test(
    'caregiver database path enforces patient role and caregiver ownership',
    () async {
      await expectLater(
        database.savePatientCreatedByCaregiver(
          'patient-uid',
          patientProfile(),
          caregiver: profile(role: UserRole.patient),
        ),
        throwsStateError,
      );
      await expectLater(
        database.savePatientCreatedByCaregiver('patient-uid', {
          ...patientProfile(),
          'caregiverId': 'other',
        }, caregiver: profile()),
        throwsStateError,
      );
      await expectLater(
        database.savePatientCreatedByCaregiver(
          'other-patient',
          patientProfile(),
          caregiver: profile(),
        ),
        throwsStateError,
      );
      expect(await (await database.database).query('patients'), isEmpty);
    },
  );
}
