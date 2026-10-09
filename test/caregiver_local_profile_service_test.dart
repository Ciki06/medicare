import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/user_model.dart';
import 'package:medicare/models/user_role.dart';
import 'package:medicare/services/caregiver_local_profile_service.dart';
import 'package:medicare/services/caregiver_sqlite_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'caregiver_sqlite_service_test.dart' show profile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late CaregiverSqliteService database;
  String? uid;
  late Future<UserModel?> Function(String) readProfile;
  late CaregiverLocalProfileService service;
  int reads = 0;
  setUp(() {
    database = CaregiverSqliteService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    uid = 'caregiver-uid';
    reads = 0;
    readProfile = (_) async {
      reads++;
      return profile();
    };
    service = CaregiverLocalProfileService(
      database: database,
      currentUid: () => uid,
      loadProfile: (id) => readProfile(id),
      uidChanges: const Stream.empty(),
    );
  });
  tearDown(() => database.close());

  test(
    'loading SQLite never reads Firebase or automatically saves a profile',
    () async {
      expect(await service.load('caregiver-uid'), isNull);
      expect(reads, 0);
      expect(await (await database.database).query('caregivers'), isEmpty);
    },
  );
  test(
    'explicit save reads the current profile and stores only that account',
    () async {
      final saved = await service.saveCurrentProfile('caregiver-uid');
      expect(reads, 1);
      expect(saved.firebaseUid, uid);
      expect((await service.load('caregiver-uid'))!.name, 'Caregiver One');
      expect(reads, 1);
    },
  );
  test('signed out and mismatched sessions cannot read or save', () async {
    for (final session in [null, 'another-uid']) {
      uid = session;
      await expectLater(service.load('caregiver-uid'), throwsStateError);
      await expectLater(
        service.saveCurrentProfile('caregiver-uid'),
        throwsStateError,
      );
    }
    expect(reads, 0);
  });
  test(
    'account change while fetching Firebase prevents a stale write',
    () async {
      final fetch = Completer<UserModel?>();
      readProfile = (_) => fetch.future;
      final saving = service.saveCurrentProfile('caregiver-uid');
      uid = 'another-uid';
      fetch.complete(profile());
      await expectLater(saving, throwsStateError);
      expect(await database.getCaregiver('caregiver-uid'), isNull);
    },
  );
  test(
    'missing, wrong-role, and wrong-UID Firebase profiles are rejected',
    () async {
      for (final result in [
        null,
        profile(role: UserRole.patient),
        profile(uid: 'another-uid'),
      ]) {
        readProfile = (_) async => result;
        await expectLater(
          service.saveCurrentProfile('caregiver-uid'),
          throwsStateError,
        );
      }
      expect(await database.getCaregiver('caregiver-uid'), isNull);
    },
  );
  test(
    'Firebase read failure leaves the previous SQLite profile unchanged',
    () async {
      final first = await service.saveCurrentProfile('caregiver-uid');
      readProfile = (_) async => throw StateError('Server unavailable');
      await expectLater(
        service.saveCurrentProfile('caregiver-uid'),
        throwsStateError,
      );
      final saved = (await database.getCaregiver('caregiver-uid'))!;
      expect(saved.name, first.name);
      expect(saved.updatedAt, first.updatedAt);
    },
  );
}
