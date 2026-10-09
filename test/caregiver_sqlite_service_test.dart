import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/user_model.dart';
import 'package:medicare/models/user_role.dart';
import 'package:medicare/services/caregiver_sqlite_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

UserModel profile({
  String uid = 'caregiver-uid',
  String name = 'Caregiver One',
  String email = 'caregiver@example.invalid',
  String? phone = '0123456789',
  String? image = 'https://example.invalid/profile.jpg?token=secret',
  UserRole role = UserRole.caregiver,
}) => UserModel(
  uid: uid,
  name: name,
  email: email,
  phone: phone,
  profilePicUrl: image,
  role: role,
  createdAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late CaregiverSqliteService service;
  setUp(() {
    service = CaregiverSqliteService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });
  tearDown(() => service.close());

  test(
    'shared database opens at version 8 and retains all role tables',
    () async {
      final db = await service.database;
      expect(db.isOpen, isTrue);
      expect(await db.getVersion(), 8);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
      );
      expect(
        tables.map((row) => row['name']),
        containsAll([
          'caregivers',
          'patients',
          'patient_medical_history',
          'family_members',
          'patient_family_links',
          'pharmacists',
          'patient_medication_cache',
          'patient_appointment_cache',
        ]),
      );
      expect(
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );
      final columns = await db.rawQuery('PRAGMA table_info(caregivers)');
      expect(columns.map((row) => row['name']), [
        'caregiver_id',
        'firebase_uid',
        'name',
        'email',
        'phone',
        'profile_pic_url',
        'created_at',
        'updated_at',
      ]);
      expect(columns.first['pk'], 1);
    },
  );

  test(
    'insert and lookup use Firebase UID and omit image access tokens',
    () async {
      expect(await service.getCaregiver('caregiver-uid'), isNull);
      final saved = await service.saveCaregiver(
        profile(),
        authenticatedUid: 'caregiver-uid',
      );
      final loaded = (await service.getCaregiver('caregiver-uid'))!;
      expect(loaded.caregiverId, saved.caregiverId);
      expect(loaded.caregiverId, greaterThan(0));
      expect(loaded.firebaseUid, 'caregiver-uid');
      expect(loaded.name, 'Caregiver One');
      expect(loaded.email, 'caregiver@example.invalid');
      expect(loaded.phone, '0123456789');
      expect(Uri.parse(loaded.profilePicUrl!).query, isEmpty);
      expect(loaded.profilePicUrl, 'https://example.invalid/profile.jpg');
      expect(loaded.profilePicUrl, isNot(contains('secret')));
      expect(loaded.createdAt.isUtc, isTrue);
      expect(await service.getCaregiver('another-uid'), isNull);
    },
  );

  test(
    'repeated saves update one row without changing its primary key',
    () async {
      final first = await service.saveCaregiver(
        profile(),
        authenticatedUid: 'caregiver-uid',
      );
      final second = await service.saveCaregiver(
        profile(name: 'Updated Name'),
        authenticatedUid: 'caregiver-uid',
      );
      expect(second.name, 'Updated Name');
      expect(second.caregiverId, first.caregiverId);
      expect(second.createdAt, first.createdAt);
      expect(second.updatedAt.isBefore(first.updatedAt), isFalse);
      expect(await (await service.database).query('caregivers'), hasLength(1));
    },
  );

  test('database uniqueness rejects direct duplicate Firebase UIDs', () async {
    await service.saveCaregiver(profile(), authenticatedUid: 'caregiver-uid');
    final db = await service.database;
    final row = Map<String, Object?>.from((await db.query('caregivers')).single)
      ..remove('caregiver_id');
    await expectLater(
      db.insert('caregivers', row),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('caregivers'), hasLength(1));
  });

  test('concurrent saves cannot create duplicate caregiver records', () async {
    final records = await Future.wait(
      List.generate(
        5,
        (i) => service.saveCaregiver(
          profile(name: 'Name $i'),
          authenticatedUid: 'caregiver-uid',
        ),
      ),
    );
    expect(records.map((record) => record.caregiverId).toSet(), hasLength(1));
    expect(await (await service.database).query('caregivers'), hasLength(1));
  });

  test(
    'null and blank values preserve every previously saved profile value',
    () async {
      final first = await service.saveCaregiver(
        profile(),
        authenticatedUid: 'caregiver-uid',
      );
      final second = await service.saveCaregiver(
        profile(name: ' ', email: '', phone: null, image: null),
        authenticatedUid: 'caregiver-uid',
      );
      expect(second.name, first.name);
      expect(second.email, first.email);
      expect(second.phone, first.phone);
      expect(second.profilePicUrl, first.profilePicUrl);
      expect(second.updatedAt, first.updatedAt);
      final third = await service.saveCaregiver(
        profile(phone: ' ', image: ' '),
        authenticatedUid: 'caregiver-uid',
      );
      expect(third.phone, first.phone);
      expect(third.profilePicUrl, first.profilePicUrl);
    },
  );

  test('incomplete new profiles and other roles are rejected', () async {
    await expectLater(
      service.saveCaregiver(
        profile(name: ''),
        authenticatedUid: 'caregiver-uid',
      ),
      throwsStateError,
    );
    for (final role in [
      UserRole.patient,
      UserRole.family,
      UserRole.pharmacist,
    ]) {
      await expectLater(
        service.saveCaregiver(
          profile(role: role),
          authenticatedUid: 'caregiver-uid',
        ),
        throwsStateError,
      );
    }
    expect(await (await service.database).query('caregivers'), isEmpty);
  });

  test('mismatched and empty authenticated UIDs are rejected', () async {
    await expectLater(
      service.saveCaregiver(profile(), authenticatedUid: 'other'),
      throwsStateError,
    );
    await expectLater(
      service.saveCaregiver(profile(uid: ''), authenticatedUid: ''),
      throwsStateError,
    );
    await expectLater(service.getCaregiver(' '), throwsArgumentError);
  });

  test('two caregiver accounts remain separate', () async {
    final first = await service.saveCaregiver(
      profile(),
      authenticatedUid: 'caregiver-uid',
    );
    final second = await service.saveCaregiver(
      profile(uid: 'second-uid', name: 'Second'),
      authenticatedUid: 'second-uid',
    );
    expect(second.caregiverId, isNot(first.caregiverId));
    expect((await service.getCaregiver('caregiver-uid'))!.name, first.name);
    expect((await service.getCaregiver('second-uid'))!.name, 'Second');
  });

  test('record persists after closing and reopening a file database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'medicare-caregiver-test-',
    );
    final persistent = CaregiverSqliteService(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/caregiver.db',
    );
    try {
      final first = await persistent.saveCaregiver(
        profile(),
        authenticatedUid: 'caregiver-uid',
      );
      await persistent.close();
      expect(
        (await persistent.getCaregiver('caregiver-uid'))!.caregiverId,
        first.caregiverId,
      );
    } finally {
      await persistent.close();
      await directory.delete(recursive: true);
    }
  });
}
