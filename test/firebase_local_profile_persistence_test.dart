import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicare/models/user_role.dart';
import 'package:medicare/models/medication_model.dart';
import 'package:medicare/services/auth_service.dart';
import 'package:medicare/services/caregiver_sqlite_service.dart';
import 'package:medicare/services/firestore_service.dart';
import 'package:medicare/services/local_profile_persistence_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'caregiver_profile_entry_test.dart' show TestCore;
import 'caregiver_sqlite_service_test.dart' show profile;
import 'patient_sqlite_service_test.dart' show patientProfile;

class AccountUser extends UserPlatform {
  AccountUser(AccountAuth auth, String uid, String email)
    : super(
        auth,
        AccountMultiFactor(auth),
        PigeonUserDetails(
          userInfo: PigeonUserInfo(
            uid: uid,
            email: email,
            isAnonymous: false,
            isEmailVerified: false,
          ),
          providerData: [],
        ),
      );
}

class AccountMultiFactor extends MultiFactorPlatform {
  AccountMultiFactor(super.auth);
}

class AccountCredential extends UserCredentialPlatform {
  AccountCredential({required super.auth, required super.user});
}

class AccountAuth extends FirebaseAuthPlatform {
  final events = StreamController<UserPlatform?>.broadcast();
  UserPlatform? active;
  String nextUid = 'patient-uid';
  int signIns = 0;
  int signUps = 0;
  bool fail = false;
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) => this;
  @override
  UserPlatform? get currentUser => active;
  @override
  Stream<UserPlatform?> authStateChanges() => events.stream;
  @override
  Future<UserCredentialPlatform> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    if (fail) {
      throw firebase_auth.FirebaseAuthException(code: 'invalid-credential');
    }
    signIns++;
    active = AccountUser(this, nextUid, email);
    events.add(active);
    return AccountCredential(auth: this, user: active);
  }

  @override
  Future<UserCredentialPlatform> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    if (fail) {
      throw firebase_auth.FirebaseAuthException(code: 'email-already-in-use');
    }
    signUps++;
    active = AccountUser(this, nextUid, email);
    events.add(active);
    return AccountCredential(auth: this, user: active);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestFirebaseCoreHostApi.setUp(TestCore());
  sqfliteFfiInit();
  final auth = AccountAuth();
  FirebaseAuthPlatform.instance = auth;
  late CaregiverSqliteService database;
  late LocalProfilePersistenceService local;
  final profiles = <String, Map<String, dynamic>>{};
  final order = <String>[];
  bool failWrite = false;
  bool fromCache = false;
  bool pendingWrites = false;
  const prefix =
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const getChannel = BasicMessageChannel<Object?>(
    '$prefix.documentReferenceGet',
    FirebaseFirestoreHostApi.codec,
  );
  setUpAll(() async {
    await Firebase.initializeApp();
  });
  tearDownAll(() => auth.events.close());
  setUp(() {
    profiles.clear();
    order.clear();
    failWrite = fromCache = pendingWrites = false;
    auth.active = null;
    auth.fail = false;
    auth.nextUid = 'patient-uid';
    auth.signIns = auth.signUps = 0;
    database = CaregiverSqliteService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    local = LocalProfilePersistenceService(database: database);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<Object?>(getChannel, (
      message,
    ) async {
      final request =
          (message as List<Object?>)[1]! as DocumentReferenceRequest;
      final uid = request.path.split('/').last;
      return [
        PigeonDocumentSnapshot(
          path: request.path,
          data: profiles[uid],
          metadata: PigeonSnapshotMetadata(
            hasPendingWrites: pendingWrites,
            isFromCache: fromCache,
          ),
        ),
      ];
    });
    for (final method in ['documentReferenceSet', 'documentReferenceUpdate']) {
      messenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(
          '$prefix.$method',
          FirebaseFirestoreHostApi.codec,
        ),
        (message) async {
          final request =
              (message as List<Object?>)[1]! as DocumentReferenceRequest;
          if (failWrite) {
            return ['permission-denied', 'Mock Firebase write failed', null];
          }
          final uid = request.path.split('/').last;
          profiles[uid] = {
            ...?profiles[uid],
            ...request.data!.cast<String, dynamic>(),
          };
          order.add('firestore-success');
          return [null];
        },
      );
    }
  });
  tearDown(() async {
    await database.close();
  });

  Future<String> register({int status = 200}) => http.runWithClient(
    () => FirestoreService(localProfiles: local).createPatientAccount(
      name: 'Registered patient',
      email: 'new@example.invalid',
      password: 'test-password',
      caregiverId: 'caregiver-uid',
      icNumber: '501009-01-1234',
      gender: 'Female',
      phone: '0123456789',
      address: 'Room 12',
      medicalHistory: ['Diabetes'],
    ),
    () => MockClient((request) async {
      expect(request.url.path, '/v1/accounts:signUp');
      expect(jsonDecode(request.body)['email'], 'new@example.invalid');
      expect(await database.getPatient('new-patient-uid'), isNull);
      order.add('auth-response');
      return http.Response(
        status == 200
            ? jsonEncode({
                'localId': 'new-patient-uid',
                'idToken': 'server-token',
                'refreshToken': 'refresh-secret',
              })
            : jsonEncode({
                'error': {'message': 'EMAIL_EXISTS'},
              }),
        status,
      );
    }),
  );

  Future<String> registerFamily() => http.runWithClient(
    () => FirestoreService(localProfiles: local).createFamilyAccount(
      name: 'Registered Family',
      email: 'family@example.invalid',
      password: 'test-password',
      caregiverId: 'caregiver-uid',
      linkedPatientIds: ['not-downloaded'],
    ),
    () => MockClient((request) async {
      expect(request.url.path, '/v1/accounts:signUp');
      expect(await database.getFamily('new-family-uid'), isNull);
      order.add('family-auth-response');
      return http.Response(
        jsonEncode({'localId': 'new-family-uid', 'idToken': 'server-token'}),
        200,
      );
    }),
  );

  Future<String> registerPharmacist() => http.runWithClient(
    () => FirestoreService(localProfiles: local).createPharmacistAccount(
      name: 'Registered Pharmacist',
      email: 'pharmacist@example.invalid',
      password: 'test-password',
      caregiverId: 'caregiver-uid',
    ),
    () => MockClient((request) async {
      expect(request.url.path, '/v1/accounts:signUp');
      expect(await database.getPharmacist('new-pharmacist-uid'), isNull);
      order.add('pharmacist-auth-response');
      return http.Response(
        jsonEncode({
          'localId': 'new-pharmacist-uid',
          'idToken': 'server-token',
        }),
        200,
      );
    }),
  );

  void caregiverSession() {
    profiles['caregiver-uid'] = profile().toMap();
    auth.active = AccountUser(
      auth,
      'caregiver-uid',
      'caregiver@example.invalid',
    );
  }

  test(
    'successful auth + Firestore registration saves patient before returning, preserving caregiver session',
    () async {
      caregiverSession();
      final uid = await register();
      expect(uid, 'new-patient-uid');
      expect(order, ['auth-response', 'firestore-success']);
      final saved = (await database.getPatient(uid))!;
      expect(saved.name, 'Registered patient');
      expect(saved.dateOfBirth, '09/10/1950');
      expect(saved.medicalHistory.single.medicalHistory, 'Diabetes');
      expect(
        saved.caregiverId,
        (await database.getCaregiver('caregiver-uid'))!.caregiverId,
      );
      expect(auth.currentUser!.uid, 'caregiver-uid');
      expect(auth.signIns + auth.signUps, 0);
      final stored = (await (await database.database).query(
        'patients',
      )).toString();
      expect(stored.contains('test-password'), isFalse);
      expect(stored.contains('server-token'), isFalse);
      expect(stored.contains('refresh-secret'), isFalse);
    },
  );

  test(
    'failed auth account creation performs no Firestore/local write',
    () async {
      caregiverSession();
      await expectLater(register(status: 400), throwsException);
      expect(order, ['auth-response']);
      expect(await database.getPatient('new-patient-uid'), isNull);
      expect(await database.getCaregiver('caregiver-uid'), isNull);
    },
  );

  test(
    'failed Firestore profile creation does not save the new patient locally',
    () async {
      caregiverSession();
      failWrite = true;
      await expectLater(register(), throwsA(isA<FirebaseException>()));
      expect(await database.getPatient('new-patient-uid'), isNull);
      expect(await database.getCaregiver('caregiver-uid'), isNull);
    },
  );

  test(
    'SQLite failure leaves successful Firebase patient registration intact',
    () async {
      caregiverSession();
      await (await database.database).execute(
        "CREATE TRIGGER fail_patient BEFORE INSERT ON patients BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      expect(await register(), 'new-patient-uid');
      expect(profiles['new-patient-uid']!['name'], 'Registered patient');
      expect(await database.getPatient('new-patient-uid'), isNull);
      expect(auth.currentUser!.uid, 'caregiver-uid');
    },
  );

  test(
    'Family registration saves after Firebase and Firestore succeed',
    () async {
      caregiverSession();
      expect(await registerFamily(), 'new-family-uid');
      expect(order, ['family-auth-response', 'firestore-success']);
      final saved = await database.getFamily('new-family-uid');
      expect(saved?['name'], 'Registered Family');
      expect(saved?['linked_patients'], isEmpty);
      expect(auth.currentUser!.uid, 'caregiver-uid');
      expect(auth.signUps, 0);
    },
  );

  test(
    'Family SQLite failure does not undo successful Firebase registration',
    () async {
      caregiverSession();
      await (await database.database).execute(
        "CREATE TRIGGER fail_family BEFORE INSERT ON family_members BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      expect(await registerFamily(), 'new-family-uid');
      expect(profiles['new-family-uid']!['role'], 'family');
      expect(await database.getFamily('new-family-uid'), isNull);
    },
  );

  test(
    'Pharmacist registration saves after Firebase and Firestore succeed',
    () async {
      caregiverSession();
      expect(await registerPharmacist(), 'new-pharmacist-uid');
      expect(order, ['pharmacist-auth-response', 'firestore-success']);
      final saved = await database.getPharmacist('new-pharmacist-uid');
      expect(saved?['name'], 'Registered Pharmacist');
      expect(saved?['email'], 'pharmacist@example.invalid');
      expect(auth.currentUser!.uid, 'caregiver-uid');
      expect(auth.signUps, 0);
    },
  );

  test('Pharmacist SQLite failure does not undo Firebase registration', () async {
    caregiverSession();
    await (await database.database).execute(
      "CREATE TRIGGER fail_pharmacist BEFORE INSERT ON pharmacists BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    expect(await registerPharmacist(), 'new-pharmacist-uid');
    expect(profiles['new-pharmacist-uid']!['role'], 'pharmacist');
    expect(await database.getPharmacist('new-pharmacist-uid'), isNull);
  });

  test(
    'self-signup saves Patient and Caregiver profiles after the Firestore write',
    () async {
      final service = AuthService(localProfiles: local);
      final patient = await service.signUp(
        name: 'Patient signup',
        email: 'patient@example.invalid',
        password: 'test-password',
        role: UserRole.patient,
      );
      expect((await database.getPatient(patient.uid))!.name, 'Patient signup');
      auth.nextUid = 'caregiver-uid';
      final caregiver = await service.signUp(
        name: 'Caregiver signup',
        email: 'caregiver@example.invalid',
        password: 'test-password',
        role: UserRole.caregiver,
      );
      expect(
        (await database.getCaregiver(caregiver.uid))!.name,
        'Caregiver signup',
      );
      expect(auth.signUps, 2);
      expect(order, ['firestore-success', 'firestore-success']);
    },
  );

  test('failed self-signup does not save a local record', () async {
    failWrite = true;
    await expectLater(
      AuthService(localProfiles: local).signUp(
        name: 'Patient signup',
        email: 'patient@example.invalid',
        password: 'test-password',
        role: UserRole.patient,
      ),
      throwsA(isA<FirebaseException>()),
    );
    expect(await database.getPatient('patient-uid'), isNull);
  });

  test(
    'successful login creates and updates one local patient from Firebase',
    () async {
      profiles['patient-uid'] = {
        ...patientProfile(),
        'createdAt': DateTime.utc(2026).toIso8601String(),
      };
      final service = AuthService(localProfiles: local);
      await service.login(
        email: 'patient@example.invalid',
        password: 'test-password',
      );
      final first = (await database.getPatient('patient-uid'))!;
      profiles['patient-uid']!['name'] = 'Updated Firebase name';
      await service.login(
        email: 'patient@example.invalid',
        password: 'test-password',
      );
      final second = (await database.getPatient('patient-uid'))!;
      expect(second.patientId, first.patientId);
      expect(second.name, 'Updated Firebase name');
      expect(second.medicalHistory.length, 2);
      expect(order, isEmpty);
    },
  );

  test(
    'successful Family login saves a Family record from Firestore',
    () async {
      auth.nextUid = 'family-uid';
      profiles['family-uid'] = {
        'uid': 'family-uid',
        'role': 'family',
        'name': 'Family Login',
        'email': 'family@example.invalid',
        'createdAt': DateTime.utc(2026).toIso8601String(),
        'linkedPatientIds': ['missing-patient'],
      };
      final user = await AuthService(
        localProfiles: local,
      ).login(email: 'family@example.invalid', password: 'test-password');
      expect(user.role, UserRole.family);
      expect((await database.getFamily('family-uid'))!['name'], 'Family Login');
      expect(await database.getPatient('missing-patient'), isNull);
    },
  );

  test('Pharmacist login inserts then updates the same local record', () async {
    auth.nextUid = 'pharmacist-uid';
    profiles['pharmacist-uid'] = {
      'uid': 'pharmacist-uid',
      'role': 'pharmacist',
      'name': 'Pharmacist Login',
      'phone': '0123456789',
      'email': 'pharmacist@example.invalid',
      'createdAt': DateTime.utc(2026).toIso8601String(),
    };
    final service = AuthService(localProfiles: local);
    final user = await service.login(
      email: 'pharmacist@example.invalid',
      password: 'test-password',
    );
    final first = await database.getPharmacist('pharmacist-uid');
    expect(user.role, UserRole.pharmacist);
    expect(first?['name'], 'Pharmacist Login');
    profiles['pharmacist-uid']!['name'] = 'Updated Pharmacist';
    await service.login(
      email: 'pharmacist@example.invalid',
      password: 'test-password',
    );
    final updated = await database.getPharmacist('pharmacist-uid');
    expect(updated?['pharmacy_id'], first?['pharmacy_id']);
    expect(updated?['name'], 'Updated Pharmacist');
    expect((await (await database.database).query('pharmacists')).length, 1);
  });

  test(
    'patient medication stream returns SQLite schedules if Firestore is unavailable',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('$prefix.querySnapshot', (_) async {
        return FirebaseFirestoreHostApi.codec.encodeMessage([
          'patient-medication-cache-stream',
        ]);
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel(
          'plugins.flutter.io/firebase_firestore/query/patient-medication-cache-stream',
        ),
        (_) async => null,
      );
      final medication = Medication(
        id: 'cached-medication',
        name: 'Cached schedule',
        dosage: '1 tablet',
        time: '08:00',
        days: const ['Daily'],
        patientId: 'patient-uid',
        patientName: 'Patient One',
        caregiverId: 'caregiver-uid',
        currentStock: 8,
        intervalDays: 1,
        startDate: '2026-10-01',
      );
      await database.savePatient(
        'patient-uid',
        patientProfile(),
        authenticatedUid: 'patient-uid',
      );
      await database.replacePatientMedicationCache('patient-uid', [medication]);
      final result =
          await FirestoreService(localProfiles: local, localDatabase: database)
              .getMedicationsByPatient('patient-uid')
              .first
              .timeout(const Duration(seconds: 5));
      expect(result.single.id, 'cached-medication');
      expect(result.single.name, 'Cached schedule');
      expect(
        (await database.getCachedPatientMedications('patient-uid')).single.id,
        'cached-medication',
      );
    },
  );

  test(
    'direct Firebase login used by LoginPage saves through the AuthGate stream',
    () async {
      profiles['patient-uid'] = {
        ...patientProfile(),
        'createdAt': DateTime.utc(2026).toIso8601String(),
      };
      final loaded = AuthService(localProfiles: local).user.first;
      await firebase_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: 'patient@example.invalid',
        password: 'test-password',
      );
      expect((await loaded)!.uid, 'patient-uid');
      expect((await database.getPatient('patient-uid'))!.name, 'Patient One');
    },
  );

  test(
    'restored caregiver session saves its local profile before exposing the user',
    () async {
      caregiverSession();
      final loaded = AuthService(localProfiles: local).user.first;
      auth.events.add(auth.currentUser);
      expect((await loaded)!.role, UserRole.caregiver);
      expect(
        (await database.getCaregiver('caregiver-uid'))!.name,
        'Caregiver One',
      );
    },
  );

  test('failed login never copies a profile into SQLite', () async {
    profiles['patient-uid'] = {
      ...patientProfile(),
      'createdAt': DateTime.utc(2026).toIso8601String(),
    };
    auth.fail = true;
    await expectLater(
      AuthService(
        localProfiles: local,
      ).login(email: 'patient@example.invalid', password: 'incorrect-password'),
      throwsA(isA<firebase_auth.FirebaseAuthException>()),
    );
    expect(await database.getPatient('patient-uid'), isNull);
  });

  test(
    'local database failure cannot turn a successful login into a failed login',
    () async {
      profiles['patient-uid'] = {
        ...patientProfile(),
        'createdAt': DateTime.utc(2026).toIso8601String(),
      };
      await (await database.database).execute(
        "CREATE TRIGGER fail_patient BEFORE INSERT ON patients BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      final user = await AuthService(
        localProfiles: local,
      ).login(email: 'patient@example.invalid', password: 'test-password');
      expect(user.uid, 'patient-uid');
      expect(auth.currentUser!.uid, user.uid);
      expect(await database.getPatient('patient-uid'), isNull);
    },
  );

  test(
    'cached or pending profiles preserve local data instead of overwriting it',
    () async {
      profiles['patient-uid'] = {
        ...patientProfile(),
        'createdAt': DateTime.utc(2026).toIso8601String(),
      };
      final service = AuthService(localProfiles: local);
      await service.login(
        email: 'patient@example.invalid',
        password: 'test-password',
      );
      profiles['patient-uid']!['name'] = 'Unconfirmed profile';
      fromCache = true;
      await service.login(
        email: 'patient@example.invalid',
        password: 'test-password',
      );
      expect((await database.getPatient('patient-uid'))!.name, 'Patient One');
      fromCache = false;
      pendingWrites = true;
      await service.login(
        email: 'patient@example.invalid',
        password: 'test-password',
      );
      expect((await database.getPatient('patient-uid'))!.name, 'Patient One');
    },
  );
}
