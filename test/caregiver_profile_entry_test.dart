import 'dart:async';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/user_model.dart';
import 'package:medicare/models/user_role.dart';
import 'package:medicare/screens/auth/login_page.dart';
import 'package:medicare/screens/home/edit_profile_page.dart';
import 'package:medicare/screens/home/profile_page.dart';
import 'package:medicare/services/caregiver_local_profile_service.dart';
import 'package:medicare/services/caregiver_sqlite_service.dart';
import 'package:medicare/services/patient_local_profile_service.dart';
import 'package:medicare/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestAuth extends FirebaseAuthPlatform {
  int signOuts = 0;
  int signIns = 0;
  Completer<void> signedOut = Completer<void>();
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) => this;
  @override
  UserPlatform? get currentUser => null;
  @override
  Stream<UserPlatform?> authStateChanges() => const Stream.empty();
  @override
  Future<UserCredentialPlatform> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    expect(email, 'patient@example.invalid');
    expect(password, 'test-password');
    signIns++;
    return TestCredential(auth: this);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    signedOut.complete();
  }
}

class TestCredential extends UserCredentialPlatform {
  TestCredential({required super.auth});
}

class TestCore extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.storageBucket = 'test.appspot.com';
    return apps;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestFirebaseCoreHostApi.setUp(TestCore());
  final auth = TestAuth();
  FirebaseAuthPlatform.instance = auth;
  late UserModel user;
  int profileReads = 0;
  int profileWrites = 0;
  int loginQueries = 0;
  Source? lastSource;
  const channelPrefix =
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const getChannel = BasicMessageChannel<Object?>(
    '$channelPrefix.documentReferenceGet',
    FirebaseFirestoreHostApi.codec,
  );
  const writeMethods = [
    'documentReferenceSet',
    'documentReferenceUpdate',
    'documentReferenceDelete',
  ];

  UserModel makeUser(UserRole role) => UserModel(
    uid: 'caregiver-uid',
    name: 'Caregiver Name',
    email: 'caregiver@example.invalid',
    phone: '0123456789',
    role: role,
    createdAt: DateTime.utc(2026),
  );

  setUpAll(() async {
    await Firebase.initializeApp();
  });
  setUp(() {
    user = makeUser(UserRole.caregiver);
    profileReads = 0;
    profileWrites = 0;
    loginQueries = 0;
    lastSource = null;
    auth.signOuts = 0;
    auth.signIns = 0;
    auth.signedOut = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<Object?>(getChannel, (
      message,
    ) async {
      final request =
          (message as List<Object?>)[1]! as DocumentReferenceRequest;
      expect(request.path, 'users/${user.uid}');
      profileReads++;
      lastSource = request.source;
      return [
        PigeonDocumentSnapshot(
          path: request.path,
          data: user.toMap(),
          metadata: PigeonSnapshotMetadata(
            hasPendingWrites: false,
            isFromCache: false,
          ),
        ),
      ];
    });
    for (final method in writeMethods) {
      messenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(
          '$channelPrefix.$method',
          FirebaseFirestoreHostApi.codec,
        ),
        (_) async {
          profileWrites++;
          return [null];
        },
      );
    }
    // Outbound Firestore filters are decoded by the native host. The test only
    // needs to return a stream ID, without decoding those native filter types.
    messenger.setMockMessageHandler(
      '$channelPrefix.querySnapshot',
      (_) async => FirebaseFirestoreHostApi.codec.encodeMessage([
        'patient-family-stream',
      ]),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'plugins.flutter.io/firebase_firestore/query/patient-family-stream',
      ),
      (_) async => null,
    );
    messenger.setMockMessageHandler('$channelPrefix.queryGet', (_) async {
      loginQueries++;
      final metadata = PigeonSnapshotMetadata(
        hasPendingWrites: false,
        isFromCache: false,
      );
      return FirebaseFirestoreHostApi.codec.encodeMessage([
        PigeonQuerySnapshot(
          documents: [
            PigeonDocumentSnapshot(
              path: 'users/${user.uid}',
              data: user.toMap(),
              metadata: metadata,
            ),
          ],
          documentChanges: [],
          metadata: metadata,
        ),
      ]);
    });
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: ProfilePage(user: user)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'caregiver profile omits the storage icon and keeps existing profile functions',
    (tester) async {
      await open(tester);
      expect(find.text('Caregiver Name'), findsNWidgets(2));
      expect(find.text('caregiver@example.invalid'), findsOneWidget);
      expect(find.text('0123456789'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
      expect(find.byTooltip('Local Database'), findsNothing);
      expect(find.byIcon(Icons.storage_outlined), findsNothing);
      expect(profileReads, 1);
      expect(profileWrites, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'family and pharmacist profiles have no caregiver database entry',
    (tester) async {
      for (final role in [UserRole.family, UserRole.pharmacist]) {
        await tester.pumpWidget(const SizedBox());
        user = makeUser(role);
        await open(tester);
        expect(find.byTooltip('Local Database'), findsNothing);
        expect(find.text('Change Password'), findsOneWidget);
        expect(find.byIcon(Icons.edit), findsOneWidget);
      }
      expect(profileWrites, 0);
    },
  );

  testWidgets('Pharmacist profile omits the local SQLite record section', (
    tester,
  ) async {
    user = makeUser(UserRole.pharmacist);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: ProfilePage(user: user)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Local SQLite record'), findsNothing);
    expect(find.text('Local Pharmacy ID'), findsNothing);
    expect(find.text('Firebase UID'), findsNothing);
    expect(find.text(user.name), findsAtLeastNWidgets(1));
    expect(find.text('0123456789'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the original edit-profile navigation is retained', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfilePage), findsOneWidget);
    expect(
      tester.widget<EditProfilePage>(find.byType(EditProfilePage)).user.uid,
      user.uid,
    );
    expect(profileWrites, 0);
  });

  testWidgets('the original logout action still invokes Firebase auth', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.text('Log Out'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Log Out'));
      await auth.signedOut.future.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
    expect(auth.signOuts, 1);
    expect(profileWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'patient profile omits the storage icon and keeps original fields and permissions',
    (tester) async {
      user = UserModel(
        uid: 'patient-uid',
        name: 'Patient Name',
        email: 'patient@example.invalid',
        role: UserRole.patient,
        createdAt: DateTime.utc(2026),
        icNumber: '501009-01-1234',
        gender: 'Female',
        dateOfBirth: '09/10/1950',
        phone: '0123456789',
        address: 'Room 12',
        medicalHistory: ['Diabetes'],
      );
      await open(tester);
      expect(find.text('Patient Name'), findsNWidgets(2));
      expect(find.text('501009-01-1234'), findsOneWidget);
      expect(find.text('Diabetes'), findsOneWidget);
      expect(find.text('Linked Family Members'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byTooltip('Local Database'), findsNothing);
      expect(find.byIcon(Icons.storage_outlined), findsNothing);
      expect(profileReads, 1);
      expect(profileWrites, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'explicit patient save reads the server and never writes Firebase',
    () async {
      user = UserModel(
        uid: 'patient-uid',
        name: 'Patient Name',
        email: 'patient@example.invalid',
        role: UserRole.patient,
        createdAt: DateTime.utc(2026),
        medicalHistory: ['Diabetes'],
      );
      sqfliteFfiInit();
      final database = CaregiverSqliteService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final service = PatientLocalProfileService(
        database: database,
        currentUid: () => user.uid,
        uidChanges: const Stream.empty(),
      );
      try {
        final record = await service.saveCurrentProfile(user.uid);
        expect(record.name, user.name);
        expect(record.medicalHistory.single.medicalHistory, 'Diabetes');
        expect(lastSource, Source.server);
        expect(profileReads, 1);
        expect(profileWrites, 0);
      } finally {
        await database.close();
      }
    },
  );

  testWidgets(
    'existing patient login still queries Firebase and signs in through Auth',
    (tester) async {
      user = UserModel(
        uid: 'patient-uid',
        name: 'Patient Name',
        email: 'patient@example.invalid',
        role: UserRole.patient,
        createdAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const LoginPage()),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'patient@example.invalid',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'test-password',
      );
      await tester.ensureVisible(find.byKey(const Key('login-button')));
      await tester.tap(find.byKey(const Key('login-button')));
      await tester.pumpAndSettle();
      expect(loginQueries, 1);
      expect(auth.signIns, 1);
      expect(profileWrites, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'explicit save uses a server profile read and never writes to Firestore',
    () async {
      sqfliteFfiInit();
      final database = CaregiverSqliteService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final service = CaregiverLocalProfileService(
        database: database,
        currentUid: () => user.uid,
        uidChanges: const Stream.empty(),
      );
      try {
        final saved = await service.saveCurrentProfile(user.uid);
        expect(saved.name, user.name);
        expect(profileReads, 1);
        expect(lastSource, Source.server);
        expect(profileWrites, 0);
      } finally {
        await database.close();
      }
    },
  );
}
