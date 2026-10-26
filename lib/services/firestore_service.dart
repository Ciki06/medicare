import 'dart:async';
import 'package:flutter/foundation.dart';
import 'offline_service.dart';
import 'sos_location_service.dart';
import 'local_profile_persistence_service.dart';
import 'caregiver_sqlite_service.dart';
import 'cloud_identity_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/malaysian_ic.dart';
import '../models/medication_action.dart';
import '../models/medication_model.dart';
import '../models/mood_model.dart';
import '../models/refill_request.dart';
import '../models/chat_message.dart';
import '../models/chat_room.dart';
import '../models/sos_alert.dart';
import '../models/sos_response.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import 'medication_action_sync_service.dart';
import 'medication_completion.dart';
import 'appointment_reminder_state.dart';

class FirestoreService {
  static final _medicationActionQueue = MedicationActionSerialQueue();
  FirestoreService({
    LocalProfilePersistenceService? localProfiles,
    CaregiverSqliteService? localDatabase,
    MedicationActionSyncService? medicationActions,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _localProfiles = localProfiles ?? LocalProfilePersistenceService(),
       _localDatabase =
           localDatabase ??
           localProfiles?.database ??
           CaregiverSqliteService.instance,
       _medicationActions = medicationActions,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _authOverride = auth;

  final LocalProfilePersistenceService _localProfiles;
  final CaregiverSqliteService _localDatabase;
  final FirebaseFirestore _firestore;
  final FirebaseAuth? _authOverride;
  late final _auth =
      _authOverride ?? FirebaseAuth.instanceFor(app: _firestore.app);
  late final _ids = CloudIdentityService(
    database: _localDatabase,
    firestore: _firestore,
    auth: _auth,
  );
  final MedicationActionSyncService? _medicationActions;
  late final _actionSync =
      _medicationActions ??
      (identical(_localDatabase, CaregiverSqliteService.instance) &&
              _firestore.app.name == '[DEFAULT]'
          ? MedicationActionSyncService.instance
          : MedicationActionSyncService(
              database: _localDatabase,
              firestore: _firestore,
              currentUid: () => _auth.currentUser?.uid,
            ));
  String? get _sessionUid => _auth.currentUser?.uid;

  Future<String> _createRecord(
    String collection,
    Map<String, dynamic> values,
  ) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final key = await _ids.nextId(collection);
      try {
        await _ids.createRecord(collection, key, values);
        return key;
      } on RecordIdCollision {
        continue;
      }
    }
    throw StateError('Could not allocate a unique record ID.');
  }

  UserModel _userFromDocument(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    if (data == null) throw StateError('User profile is missing.');
    return UserModel.fromMap({...data, 'uid': document.id});
  }

  /// Rebuild this account's local mirror from confirmed cloud data at login.
  /// Only server-confirmed records replace a cache; account UIDs resolve the
  /// device's local profile IDs without a second mapping system.
  Future<void> restoreLocalRecords(UserModel account) async {
    void checkSession() {
      if (_sessionUid != account.uid) {
        throw StateError('The authenticated account changed.');
      }
    }

    checkSession();
    final patientUids = <String>[];
    if (account.role == UserRole.caregiver) {
      final managed = await _firestore
          .collection('users')
          .where('caregiverId', isEqualTo: account.uid)
          .get(const GetOptions(source: Source.server));
      checkSession();
      for (final document in managed.docs.where(
        (d) => d.data()['role'] == 'patient',
      )) {
        checkSession();
        await _localProfiles.saveCreatedPatient({
          ...document.data(),
          'uid': document.id,
        }, caregiverUid: account.uid);
        patientUids.add(document.id);
      }
      for (final document in managed.docs.where(
        (d) => d.data()['role'] == 'family',
      )) {
        await _localProfiles.saveCreatedFamily({
          ...document.data(),
          'uid': document.id,
        }, caregiverUid: account.uid);
      }
      for (final document in managed.docs.where(
        (d) => d.data()['role'] == 'pharmacist',
      )) {
        await _localProfiles.saveCreatedPharmacist({
          ...document.data(),
          'uid': document.id,
        }, caregiverUid: account.uid);
      }
    } else if (account.role == UserRole.patient) {
      patientUids.add(account.uid);
    } else if (account.role == UserRole.family) {
      patientUids.addAll(account.linkedPatientIds);
      for (final uid in patientUids) {
        final document = await _firestore
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server));
        checkSession();
        if (document.exists) {
          await _localDatabase.saveLinkedPatient(uid, {
            ...document.data()!,
            'uid': uid,
          }, family: account);
        }
      }
      // Patient profiles must exist before SQLite can build family links.
      await _localProfiles.saveAuthenticatedProfile(
        account.uid,
        account.toMap(),
      );
    }
    for (final uid in patientUids) {
      checkSession();
      Future<QuerySnapshot<Map<String, dynamic>>> records(String entity) {
        Query<Map<String, dynamic>> query = _firestore
            .collection(entity)
            .where('patientId', isEqualTo: uid);
        if (account.role == UserRole.caregiver &&
            const [
              'medications',
              'appointments',
              'refill_requests',
            ].contains(entity)) {
          query = query.where('caregiverId', isEqualTo: account.uid);
        }
        return query.get(const GetOptions(source: Source.server));
      }

      final medications = await records('medications');
      checkSession();
      await _localDatabase.replacePatientMedicationCache(
        uid,
        medications.docs
            .where((d) => d.data()['deletedAt'] == null)
            .map((d) => Medication.fromMap(d.id, d.data()))
            .toList(),
      );
      final appointments = await records('appointments');
      checkSession();
      await _localDatabase.replacePatientAppointmentCache(
        uid,
        appointments.docs
            .where((d) => d.data()['deletedAt'] == null)
            .map((d) => Appointment.fromMap(d.id, d.data()))
            .toList(),
      );
      for (final doc in (await records('medication_actions')).docs) {
        checkSession();
        await _localDatabase.saveMedicationAction(
          MedicationAction.fromMap(
            doc.id,
            doc.data(),
          ).copyWith(syncStatus: 'synced'),
          preservePending: true,
        );
      }
      final moods = await records('moods');
      checkSession();
      await _localDatabase.replacePatientMoodCache(
        uid,
        moods.docs.map((doc) => DailyMood.fromMap(doc.id, doc.data())).toList(),
      );
      if (account.role != UserRole.family) {
        for (final doc in (await records('refill_requests')).docs) {
          checkSession();
          await _localDatabase.saveRefillRequest(
            RefillRequest.fromMap(doc.id, doc.data()),
          );
        }
      }
    }
  }

  Future<UserModel?> getUserByEmail(String email) async {
    final profile = await _ids.lookupUserByEmail(email);
    return profile == null ? null : UserModel.fromMap(profile);
  }

  Stream<List<UserModel>> getUsersByCaregiver(String caregiverId) {
    return _firestore
        .collection('users')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map((snap) => snap.docs.map(_userFromDocument).toList());
  }

  Stream<List<UserModel>> getFamilyLinkedToPatient(String patientId) {
    return _firestore
        .collection('users')
        .where('linkedPatientIds', arrayContains: patientId)
        .where('role', isEqualTo: 'family')
        .snapshots()
        .map((snap) => snap.docs.map(_userFromDocument).toList());
  }

  Stream<List<UserModel>> getPatientsByCaregiver(String caregiverId) {
    return _firestore
        .collection('users')
        .where('caregiverId', isEqualTo: caregiverId)
        .where('role', isEqualTo: 'patient')
        .snapshots()
        .map((snap) => snap.docs.map(_userFromDocument).toList());
  }

  Future<List<UserModel>> getPatientsByIds(List<String> patientIds) async {
    if (patientIds.isEmpty) return const [];
    final ids = patientIds.toSet().toList();
    final result = <UserModel>[];
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(
        i,
        (i + 10) < ids.length ? (i + 10) : ids.length,
      );
      final snap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .where('role', isEqualTo: 'patient')
          .get();
      result.addAll(snap.docs.map(_userFromDocument));
    }
    return result;
  }

  Future<String> createPatientAccount({
    required String name,
    required String email,
    required String password,
    required String caregiverId,
    required String icNumber,
    required String gender,
    required String phone,
    required String address,
    List<String> medicalHistory = const [],
    String? medicalNotes,
  }) async {
    final now = DateTime.now();
    final birthDate = MalaysianIc.birthDate(icNumber);
    final dateOfBirth = birthDate?.toIso8601String().substring(0, 10);
    final user = UserModel(
      uid: '',
      name: name,
      email: email,
      role: UserRole.patient,
      createdAt: now,
      caregiverId: caregiverId,
      icNumber: icNumber,
      gender: gender,
      phone: phone,
      address: address,
      dateOfBirth: dateOfBirth,
      medicalHistory: medicalHistory,
      medicalNotes: medicalNotes,
      profilePicUrl: null,
      shortId: UserModel.generateId(UserRole.patient),
    );
    final savedProfile = await _ids.createManagedProfile(
      user.toMap(),
      password,
    );
    final uid = savedProfile['uid'] as String;
    await _localProfiles.saveCreatedPatient(
      savedProfile,
      caregiverUid: caregiverId,
    );
    return uid;
  }

  Future<String> createFamilyAccount({
    required String name,
    required String email,
    required String password,
    required String caregiverId,
    String? relationship,
    List<String> linkedPatientIds = const [],
    List<String> linkedPatientEmails = const [],
  }) async {
    final user = UserModel(
      uid: '',
      name: name,
      email: email,
      role: UserRole.family,
      relationship: relationship,
      createdAt: DateTime.now(),
      caregiverId: caregiverId,
      linkedPatientIds: linkedPatientIds,
      linkedPatientEmails: linkedPatientEmails,
      profilePicUrl: null,
      shortId: UserModel.generateId(UserRole.family),
    );
    final savedProfile = await _ids.createManagedProfile(
      user.toMap(),
      password,
    );
    final uid = savedProfile['uid'] as String;
    await _localProfiles.saveCreatedFamily(
      savedProfile,
      caregiverUid: caregiverId,
    );
    return uid;
  }

  Future<String> createPharmacistAccount({
    required String name,
    required String email,
    required String password,
    required String caregiverId,
  }) async {
    final user = UserModel(
      uid: '',
      name: name,
      email: email,
      role: UserRole.pharmacist,
      createdAt: DateTime.now(),
      caregiverId: caregiverId,
      profilePicUrl: null,
      shortId: UserModel.generateId(UserRole.pharmacist),
    );
    final savedProfile = await _ids.createManagedProfile(
      user.toMap(),
      password,
    );
    final uid = savedProfile['uid'] as String;
    await _localProfiles.saveCreatedPharmacist(
      savedProfile,
      caregiverUid: caregiverId,
    );
    return uid;
  }

  Future<String> createMedication(Medication medication) async {
    return _createRecord('medications', medication.toMap());
  }

  Stream<List<Medication>> getMedicationsByCaregiver(String caregiverId) {
    final schedules = _caregiverSchedules(
      caregiverId: caregiverId,
      collection: 'medications',
      decode: Medication.fromMap,
      replace: _localDatabase.replacePatientMedicationCache,
      compare: Medication.compareByTime,
    );
    // A pharmacist may read this caregiver's stock schedules but does not have
    // permission to read clinical action history. Keep that existing boundary.
    if (_sessionUid != caregiverId) return schedules;
    return medicationCompletionStream(
      schedules: schedules,
      actionsForPatients: getMedicationActionsByPatients,
    );
  }

  Stream<List<T>> _caregiverSchedules<T>({
    required String caregiverId,
    required String collection,
    required T Function(String id, Map<String, dynamic> data) decode,
    required Future<void> Function(String uid, List<T> rows) replace,
    required int Function(T a, T b) compare,
  }) {
    final owner = _sessionUid;
    return _firestore
        .collection(collection)
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snapshot) async {
          if (_sessionUid != owner) return <T>[];
          final grouped = <String, List<T>>{};
          final rows = <T>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final patientRows = grouped.putIfAbsent(
              data['patientId'] as String,
              () => [],
            );
            if (data['deletedAt'] != null) continue;
            final row = decode(doc.id, data);
            rows.add(row);
            patientRows.add(row);
          }
          if (!snapshot.metadata.isFromCache &&
              !snapshot.metadata.hasPendingWrites) {
            for (final entry in grouped.entries) {
              if (_sessionUid != owner) return <T>[];
              try {
                await replace(entry.key, entry.value);
              } catch (_) {}
            }
          }
          return rows..sort(compare);
        });
  }

  Stream<List<Medication>> getMedicationsByPatient(String patientId) =>
      medicationCompletionStream(
        schedules: _cachedPatientSchedule(
          patientId: patientId,
          collection: 'medications',
          load: _localDatabase.getCachedPatientMedications,
          replace: _localDatabase.replacePatientMedicationCache,
          decode: Medication.fromMap,
          compare: Medication.compareByTime,
          recordId: (medication) => medication.id,
          reportErrors: true,
        ),
        actionsForPatients: (_) =>
            _patientMedicationActions(patientId, reportErrors: true),
      );

  /// Cached and optimistic snapshots are useful for display, but only a full
  /// server acknowledgement may delete or replace confirmed SQLite schedules.
  Stream<List<T>> _cachedPatientSchedule<T>({
    required String patientId,
    required String collection,
    required Future<List<T>> Function(String uid) load,
    required Future<void> Function(String uid, List<T> rows) replace,
    required T Function(String id, Map<String, dynamic> data) decode,
    required int Function(T a, T b) compare,
    required String Function(T row) recordId,
    bool reportErrors = false,
  }) {
    if (patientId.trim().isEmpty) return Stream.value(const []);
    final owner = _sessionUid;
    final controller = StreamController<List<T>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
    var cancelled = false;
    var confirmed = false;
    var remoteFailed = false;
    var local = <T>[];
    var cached = <T>[];
    Future<void> writes = Future.value();
    bool active() => !cancelled && _sessionUid == owner;
    void emitCached() {
      if (!active()) return;
      final merged = <String, T>{
        for (final row in local) recordId(row): row,
        for (final row in cached) recordId(row): row,
      };
      final rows = merged.values.toList()..sort(compare);
      controller.add(rows);
    }

    controller.onListen = () {
      unawaited(() async {
        try {
          local = await load(patientId);
          if (!confirmed && (!reportErrors || !remoteFailed)) emitCached();
        } catch (error, stack) {
          if (reportErrors && active() && !confirmed) {
            controller.addError(error, stack);
          }
        }
      }());
      subscription = _firestore
          .collection(collection)
          .where('patientId', isEqualTo: patientId)
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) {
              if (!active()) return;
              late final List<T> rows;
              try {
                rows =
                    snapshot.docs
                        .where((doc) => doc.data()['deletedAt'] == null)
                        .map((doc) => decode(doc.id, doc.data()))
                        .toList()
                      ..sort(compare);
              } catch (error, stack) {
                debugPrint(
                  'Invalid $collection snapshot was not applied (${error.runtimeType}).',
                );
                if (reportErrors) {
                  remoteFailed = true;
                  controller.addError(error, stack);
                }
                return;
              }
              remoteFailed = false;
              if (snapshot.metadata.isFromCache ||
                  snapshot.metadata.hasPendingWrites) {
                cached = rows;
                if (!confirmed) {
                  emitCached();
                } else {
                  controller.add(rows);
                }
                return;
              }
              confirmed = true;
              controller.add(rows);
              writes = writes.then((_) async {
                if (!active()) return;
                try {
                  await replace(patientId, rows);
                } catch (_) {}
              });
            },
            onError: (Object error, StackTrace stack) {
              debugPrint(
                '$collection listener deferred (${error.runtimeType}).',
              );
              if (reportErrors && active()) {
                remoteFailed = true;
                controller.addError(error, stack);
              }
            },
          );
    };
    controller.onCancel = () async {
      cancelled = true;
      await subscription?.cancel();
    };
    return controller.stream;
  }

  Future<String> createAppointment(Appointment appointment) async {
    return _createRecord('appointments', appointment.toMap());
  }

  Future<void> updateAppointment(Appointment appointment) async {
    return _firestore
        .collection('appointments')
        .doc(appointment.id)
        .update(
          await _ids.encode(
            'appointments',
            appointment.id,
            appointment.toMap(),
          ),
        );
  }

  Future<void> updateAppointmentStatus(String appointmentId, String status) {
    return OfflineService.save(
      _firestore.collection('appointments').doc(appointmentId).update({
        'status': status,
      }),
    );
  }

  Future<Appointment?> getAppointmentById(String appointmentId) async {
    final record = await _firestore
        .collection('appointments')
        .doc(appointmentId)
        .get();
    final data = record.data();
    return data == null || data['deletedAt'] != null
        ? null
        : Appointment.fromMap(record.id, data);
  }

  /// The fingerprint acknowledges this schedule only. Changing the date, time
  /// or advance interval re-arms its reminder without losing completion state.
  Future<void> markAppointmentReminderViewed(Appointment appointment) async {
    await OfflineService.save(
      _firestore.collection('appointments').doc(appointment.id).update({
        'reminderViewedFor': appointment.reminderKey,
      }),
    );
    await AppointmentReminderState.remember(appointment);
  }

  Future<List<Appointment>> getAppointmentsByCaregiverOnce(
    String caregiverId,
  ) async {
    final snap = await _firestore
        .collection('appointments')
        .where('caregiverId', isEqualTo: caregiverId)
        .get();
    return snap.docs
        .where((d) => d.data()['deletedAt'] == null)
        .map((d) => Appointment.fromMap(d.id, d.data()))
        .toList();
  }

  Future<void> updateMedication(Medication medication) async {
    return _firestore
        .collection('medications')
        .doc(medication.id)
        .update(
          await _ids.encode('medications', medication.id, medication.toMap()),
        );
  }

  Stream<List<Appointment>> getAppointmentsByCaregiver(String caregiverId) =>
      _caregiverSchedules(
        caregiverId: caregiverId,
        collection: 'appointments',
        decode: Appointment.fromMap,
        replace: _localDatabase.replacePatientAppointmentCache,
        compare: Appointment.compareChronologically,
      );
  Stream<List<Appointment>> getAppointmentsByPatient(String patientId) =>
      _cachedPatientSchedule(
        patientId: patientId,
        collection: 'appointments',
        load: _localDatabase.getCachedPatientAppointments,
        replace: _localDatabase.replacePatientAppointmentCache,
        decode: Appointment.fromMap,
        compare: Appointment.compareChronologically,
        recordId: (appointment) => appointment.id,
      ).asyncMap(
        (appointments) =>
            AppointmentReminderState.restore(patientId, appointments),
      );
  Future<String> addMedication({
    required String caregiverId,
    required String patientId,
    required String patientName,
    required String name,
    required String type,
    required String dosage,
    required String time,
    List<String> days = const ['Daily'],
    String? startDate,
    int intervalDays = 1,
    int currentStock = 0,
    String? imageUrl,
    bool remindRefill = true,
    int remindThreshold = 5,
  }) async {
    final med = Medication(
      id: '',
      name: name,
      dosage: dosage,
      time: time,
      days: days,
      startDate: startDate,
      intervalDays: intervalDays,
      patientId: patientId,
      patientName: patientName,
      caregiverId: caregiverId,
      type: type,
      currentStock: currentStock,
      imageUrl: imageUrl,
      remindRefill: remindRefill,
      remindThreshold: remindThreshold,
    );
    return _createRecord('medications', med.toMap());
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    final changes = {...data}..remove('linkedPatientEmails');
    if (changes.isEmpty) return;
    final saved = await _ids.updateProfile(uid, changes);
    if (_sessionUid == uid) {
      await _localProfiles.saveAuthenticatedProfile(uid, saved);
    }
  }

  Future<String> createRefillRequest(RefillRequest request) async {
    final key = await _createRecord(
      'refill_requests',
      request.copyWith(status: 'pending').toMap(),
    );
    final savedRequest = request.copyWith(id: key, status: 'pending');
    // Firestore acknowledgement is required before the local insert.
    try {
      await _localDatabase.saveRefillRequest(savedRequest);
    } catch (error) {
      // The request is already server-confirmed; login sync will retry caching.
      debugPrint(
        'Refill request saved remotely but local cache failed: $error',
      );
    }
    return key;
  }

  Stream<List<RefillRequest>> getRefillRequestsByCaregiver(String caregiverId) {
    return _firestore
        .collection('refill_requests')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map((d) => RefillRequest.fromMap(d.id, d.data()))
                  .toList()
                ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
        );
  }

  Stream<List<RefillRequest>> getRefillRequestsByPatient(String patientId) {
    return _firestore
        .collection('refill_requests')
        .where('patientId', isEqualTo: patientId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map((d) => RefillRequest.fromMap(d.id, d.data()))
                  .toList()
                ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
        );
  }

  Stream<List<RefillRequest>> getAllRefillRequests() {
    final owner = _sessionUid;
    if (owner == null) return Stream.value(const []);
    return Stream.fromFuture(getUserById(owner)).asyncExpand((profile) {
      final caregiverId = profile?.caregiverId;
      if (_sessionUid != owner ||
          profile?.role != UserRole.pharmacist ||
          caregiverId == null) {
        return Stream.value(<RefillRequest>[]);
      }
      return _firestore
          .collection('refill_requests')
          .where('caregiverId', isEqualTo: caregiverId)
          .snapshots(includeMetadataChanges: true)
          .map(
            (snap) =>
                snap.docs
                    .map((d) => RefillRequest.fromMap(d.id, d.data()))
                    .toList()
                  ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
          );
    });
  }

  Future<void> updateRefillRequestStatus(
    String requestId,
    String status,
  ) async {
    final owner = _sessionUid;
    final result =
        await FirebaseFunctions.instanceFor(
          app: _firestore.app,
          region: 'asia-southeast1',
        ).httpsCallable('updateRefillRequestStatus').call({
          'requestId': requestId,
          'status': status,
        });
    if (owner != _sessionUid) return;
    final response = Map<String, dynamic>.from(result.data as Map);
    try {
      await _localDatabase.saveRefillRequest(
        RefillRequest.fromMap(
          requestId,
          Map<String, dynamic>.from(response['request'] as Map),
        ),
      );
    } catch (error) {
      debugPrint(
        'Confirmed refill status could not be cached (${error.runtimeType}).',
      );
    }
  }

  Future<void> logMedicationAction({
    required String medicationId,
    required String medicationName,
    required String patientId,
    required String action,
    int? snoozedUntil,
  }) => _medicationActionQueue.run(
    patientId,
    medicationId,
    () => _saveMedicationAction(
      medicationId: medicationId,
      medicationName: medicationName,
      patientId: patientId,
      action: action,
      snoozedUntil: snoozedUntil,
    ),
  );

  Future<void> _saveMedicationAction({
    required String medicationId,
    required String medicationName,
    required String patientId,
    required String action,
    int? snoozedUntil,
  }) async {
    if (_sessionUid != patientId) {
      throw StateError('Only the signed-in patient can record an action.');
    }
    if (!const {'taken', 'skipped', 'snoozed'}.contains(action)) {
      throw ArgumentError.value(action, 'action');
    }
    if (action == 'taken') {
      Medication? medication;
      for (final cached in await _localDatabase.getCachedPatientMedications(
        patientId,
      )) {
        if (cached.id == medicationId) {
          medication = cached;
          break;
        }
      }
      if (medication == null) {
        // A first-login Firestore snapshot may reach a screen before the full
        // acknowledged schedule has been mirrored into SQLite.
        try {
          final cached = await _firestore
              .collection('medications')
              .doc(medicationId)
              .get(const GetOptions(source: Source.cache));
          if (cached.exists && cached.data()?['patientId'] == patientId) {
            medication = Medication.fromMap(cached.id, cached.data()!);
          }
        } on FirebaseException catch (_) {
          // Existing schedules remain actionable when Firestore cache is empty.
        }
      }
      if (medication?.isOnce == true &&
          projectMedicationCompletion(
            [medication!],
            await _localDatabase.getMedicationActions(patientId),
          ).single.isCompleted) {
        return;
      }
    }
    if (_sessionUid != patientId) {
      throw StateError('The authenticated account changed.');
    }
    final actionRecord = MedicationAction(
      id: await _ids.nextId('medication_actions'),
      medicationId: medicationId,
      medicationName: medicationName,
      patientId: patientId,
      action: action,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      snoozedUntil: snoozedUntil,
      syncStatus: 'pending',
    );
    // The durable local insert completes before the patient flow continues.
    // One worker handles immediate upload, reconnection, restart and retries.
    await _localDatabase.saveMedicationAction(actionRecord);
    await _actionSync
        .startForPatient(patientId)
        .timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  Stream<List<MedicationAction>> getMedicationActionsByPatient(
    String patientId,
  ) => _patientMedicationActions(patientId);

  Stream<List<MedicationAction>> _patientMedicationActions(
    String patientId, {
    bool reportErrors = false,
  }) {
    final owner = _sessionUid;
    late final StreamController<List<MedicationAction>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? firestoreSub;
    StreamSubscription<String>? localSub;
    var cancelled = false;
    Future<void> cacheWrites = Future.value();
    List<MedicationAction> remoteActions = const [];
    var remoteHistoryLoaded = false;

    Future<void> emitMerged() async {
      if (cancelled || _sessionUid != owner) return;
      try {
        final localActions = await _localDatabase.getMedicationActions(
          patientId,
        );
        if (cancelled || _sessionUid != owner) return;
        final merged = <String, MedicationAction>{
          for (final action in remoteActions) action.id: action,
          for (final action in localActions) action.id: action,
        };
        final result = merged.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        controller.add(result);
      } catch (error, stack) {
        if (cancelled || _sessionUid != owner) return;
        if (remoteHistoryLoaded) {
          controller.add(remoteActions);
        } else if (reportErrors) {
          // Let the completion join finish with usable schedules instead of
          // waiting forever when the local history cache cannot be read.
          controller.addError(error, stack);
        }
      }
    }

    controller = StreamController(
      onListen: () {
        if (patientId.trim().isEmpty) {
          controller.add(const []);
          return;
        }
        unawaited(emitMerged());
        localSub = _localDatabase.medicationActionChanges
            .where((uid) => uid == patientId)
            .listen((_) => unawaited(emitMerged()));
        firestoreSub = _firestore
            .collection('medication_actions')
            .where('patientId', isEqualTo: patientId)
            .orderBy('timestamp', descending: true)
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                if (cancelled || _sessionUid != owner) return;
                remoteHistoryLoaded = true;
                remoteActions = snapshot.docs.map((doc) {
                  final action = MedicationAction.fromMap(doc.id, doc.data());
                  return action.copyWith(
                    syncStatus: doc.metadata.hasPendingWrites
                        ? 'pending'
                        : 'synced',
                  );
                }).toList();
                cacheWrites = cacheWrites.then((_) async {
                  if (cancelled ||
                      _sessionUid != owner ||
                      snapshot.metadata.isFromCache ||
                      snapshot.metadata.hasPendingWrites) {
                    return;
                  }
                  for (final doc in snapshot.docs) {
                    if (!doc.metadata.hasPendingWrites &&
                        !cancelled &&
                        _sessionUid == owner) {
                      final action = MedicationAction.fromMap(
                        doc.id,
                        doc.data(),
                      );
                      try {
                        await _localDatabase.saveMedicationAction(
                          action.copyWith(syncStatus: 'synced'),
                          preservePending: true,
                        );
                      } catch (_) {
                        // Firebase history remains available if SQLite is unavailable.
                      }
                    }
                  }
                });
                unawaited(emitMerged());
              },
              onError: (Object error, StackTrace stack) {
                if (reportErrors && !cancelled && _sessionUid == owner) {
                  controller.addError(error, stack);
                }
                unawaited(emitMerged());
              },
            );
      },
      onCancel: () async {
        cancelled = true;
        await firestoreSub?.cancel();
        await localSub?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<List<MedicationAction>> getMedicationActionsByPatients(
    List<String> patientIds,
  ) {
    return _patientRecords('medication_actions', patientIds).map(
      (docs) =>
          docs.map((d) => MedicationAction.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
    );
  }

  Stream<List<DailyMood>> getMoodHistory(List<String> patientIds) =>
      _patientRecords('moods', patientIds).map(
        (docs) =>
            docs.map((d) => DailyMood.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
      );

  Stream<List<Medication>> getMedicationsByPatients(List<String> ids) =>
      medicationCompletionStream(
        schedules: _patientRecords('medications', ids).map(
          (docs) => docs
              .where((d) => d.data()['deletedAt'] == null)
              .map((d) => Medication.fromMap(d.id, d.data()))
              .toList(),
        ),
        actionsForPatients: getMedicationActionsByPatients,
      );

  Stream<List<Appointment>> getAppointmentsByPatients(
    List<String> patientIds,
  ) => _patientRecords('appointments', patientIds).map(
    (docs) => docs
        .where((d) => d.data()['deletedAt'] == null)
        .map((d) => Appointment.fromMap(d.id, d.data()))
        .toList(),
  );

  // Fan out every chunk; never silently drop patients after Firestore's limit.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _patientRecords(
    String collection,
    List<String> patientIds, {
    String? date,
  }) {
    final ids = patientIds.toSet().toList();
    if (ids.isEmpty) return Stream.value([]);
    final owner = _sessionUid;
    var cancelled = false;
    Future<void> cacheWrites = Future.value();
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    final latest = <int, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    late StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    controller;
    final chunks = <List<String>>[
      for (var i = 0; i < ids.length; i += 10)
        ids.sublist(i, i + 10 < ids.length ? i + 10 : ids.length),
    ];
    final count = chunks.length;
    controller = StreamController(
      onListen: () {
        for (var i = 0; i < count; i++) {
          final chunk = chunks[i];
          Query<Map<String, dynamic>> query = _firestore
              .collection(collection)
              .where('patientId', whereIn: chunk);
          if (date != null) query = query.where('date', isEqualTo: date);
          subscriptions.add(
            query.snapshots(includeMetadataChanges: true).listen((snapshot) {
              if (cancelled || _sessionUid != owner) return;
              latest[i] = snapshot.docs;
              if (latest.length == count) {
                controller.add(latest.values.expand((docs) => docs).toList());
              }
              if (!snapshot.metadata.isFromCache &&
                  !snapshot.metadata.hasPendingWrites) {
                cacheWrites = cacheWrites.then((_) async {
                  for (final patientUid in chunk) {
                    if (cancelled || _sessionUid != owner) return;
                    final documents = snapshot.docs
                        .where((doc) => doc.data()['patientId'] == patientUid)
                        .toList();
                    try {
                      switch (collection) {
                        case 'moods':
                          if (date == null) {
                            await _localDatabase.replacePatientMoodCache(
                              patientUid,
                              documents
                                  .map(
                                    (doc) =>
                                        DailyMood.fromMap(doc.id, doc.data()),
                                  )
                                  .toList(),
                            );
                          } else {
                            for (final change in snapshot.docChanges.where(
                              (change) =>
                                  change.doc.data()?['patientId'] == patientUid,
                            )) {
                              if (change.type == DocumentChangeType.removed) {
                                await _localDatabase.deleteMood(change.doc.id);
                              } else {
                                await _localDatabase.saveMood(
                                  DailyMood.fromMap(
                                    change.doc.id,
                                    change.doc.data()!,
                                  ),
                                );
                              }
                            }
                          }
                        case 'medications':
                          await _localDatabase.replacePatientMedicationCache(
                            patientUid,
                            documents
                                .where((doc) => doc.data()['deletedAt'] == null)
                                .map(
                                  (doc) =>
                                      Medication.fromMap(doc.id, doc.data()),
                                )
                                .toList(),
                          );
                        case 'appointments':
                          await _localDatabase.replacePatientAppointmentCache(
                            patientUid,
                            documents
                                .where((doc) => doc.data()['deletedAt'] == null)
                                .map(
                                  (doc) =>
                                      Appointment.fromMap(doc.id, doc.data()),
                                )
                                .toList(),
                          );
                        case 'medication_actions':
                          for (final doc in documents) {
                            await _localDatabase.saveMedicationAction(
                              MedicationAction.fromMap(doc.id, doc.data()),
                              preservePending: true,
                            );
                          }
                      }
                    } catch (_) {}
                  }
                });
              }
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        cancelled = true;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Future<void> updateMedicationImage(String medId, String imageUrl) async {
    await _firestore.collection('medications').doc(medId).update({
      'imageUrl': imageUrl,
    });
  }

  Future<void> deleteMedication(String medId) async {
    await _firestore.collection('medications').doc(medId).update({
      'deletedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteAppointment(String appointmentId) async {
    await _firestore.collection('appointments').doc(appointmentId).update({
      'deletedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> saveMood({
    required String patientId,
    required int moodIndex,
    required String moodLabel,
    required String emoji,
    required String date,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final mood = DailyMood(
      id: '',
      patientId: patientId,
      moodIndex: moodIndex,
      moodLabel: moodLabel,
      emoji: emoji,
      date: date,
      timestamp: timestamp,
    );
    // Await the Firestore write directly: its Future completes only after the
    // server acknowledges it. Never add an unconfirmed write to SQLite.
    final key = await _createRecord('moods', mood.toMap());
    await _localDatabase.saveMood(
      DailyMood.fromMap(key, {...mood.toMap(), 'id': key}),
    );
  }

  Stream<DailyMood?> getTodayMood(String patientId, String date) {
    return _patientRecords('moods', [patientId], date: date).map((records) {
      if (records.isEmpty) return null;
      final docs = records.toList()
        ..sort((a, b) {
          final aTime = (a.data()['timestamp'] as num?)?.toInt() ?? 0;
          final bTime = (b.data()['timestamp'] as num?)?.toInt() ?? 0;
          return bTime.compareTo(aTime);
        });
      return DailyMood.fromMap(docs.first.id, docs.first.data());
    });
  }

  Future<DailyMood?> getMoodByDate(String patientId, String date) async {
    final snap = await _firestore
        .collection('moods')
        .where('patientId', isEqualTo: patientId)
        .where('date', isEqualTo: date)
        .get();
    if (snap.docs.isEmpty) return null;
    final docs = snap.docs.toList()
      ..sort((a, b) {
        final aTime = (a.data()['timestamp'] as num?)?.toInt() ?? 0;
        final bTime = (b.data()['timestamp'] as num?)?.toInt() ?? 0;
        return bTime.compareTo(aTime);
      });
    return DailyMood.fromMap(docs.first.id, docs.first.data());
  }

  Future<void> deleteMood({
    required String patientId,
    required String date,
  }) async {
    final snap = await _firestore
        .collection('moods')
        .where('patientId', isEqualTo: patientId)
        .where('date', isEqualTo: date)
        .get();
    if (snap.docs.isEmpty) return;
    final docs = snap.docs.toList()
      ..sort((a, b) {
        final aTime = (a.data()['timestamp'] as num?)?.toInt() ?? 0;
        final bTime = (b.data()['timestamp'] as num?)?.toInt() ?? 0;
        return bTime.compareTo(aTime);
      });
    await docs.first.reference.delete();
    await _localDatabase.deleteMood(docs.first.id);
  }

  Stream<List<DailyMood>> getTodayMoodsByPatients(
    List<String> patientIds,
    String date,
  ) {
    return _patientRecords('moods', patientIds, date: date).map(
      (docs) => docs.map((d) => DailyMood.fromMap(d.id, d.data())).toList(),
    );
  }

  /// Create an SOS alert broadcast to the patient's caregiver and linked family members.
  /// Returns the id of the created alert document.
  Future<String> triggerSos(
    UserModel patient, {
    String triggerSource = 'in_app',
    void Function(Map<String, dynamic>)? onLocation,
  }) async {
    final doc = _firestore.collection('sos_alerts').doc();
    // Submit immediately; GPS must never delay the emergency alert.
    await OfflineService.save(
      doc.set({
        'patientId': patient.uid,
        'patientName': patient.name,
        'caregiverId': patient.caregiverId ?? '',
        // A trusted Cloud Function resolves recipients from the current user
        // relationships; clients cannot choose notification targets.
        'alertUserIds': <String>[],
        'status': 'active',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'triggerSource': triggerSource,
        'locationStatus': 'pending',
      }),
    );
    unawaited(
      SosLocationService.capture()
          .then((location) async {
            await OfflineService.save(doc.update(location));
            onLocation?.call(location);
          })
          .catchError((Object e) {
            OfflineService.error.value = 'SOS location could not sync: $e';
          }),
    );
    return doc.id;
  }

  /// Stream the patient's own SOS alerts (any status), newest first.
  /// Replies still need to be visible right after a caregiver acknowledges an
  /// alert, so no status filter is applied here.
  Stream<List<SosAlert>> streamSosAlertsForPatient(String patientId) {
    return _firestore
        .collection('sos_alerts')
        .where('patientId', isEqualTo: patientId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => SosAlert.fromMap(d.id, d.data())).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  /// Stream replies ("on the way" messages) sent in response to one alert,
  /// newest first. Stored as a subcollection so it is automatically scoped to
  /// the alert and needs no extra indexes.
  Stream<List<SosResponse>> streamSosResponsesForAlert(String alertId) {
    if (alertId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('sos_alerts')
        .doc(alertId)
        .collection('responses')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => SosResponse.fromMap(d.id, d.data())).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  /// Send an "on the way" reply from a caregiver / family member to the
  /// patient who triggered the alert. Firestore rules enforce that only
  /// recipients of an active alert can write, and only their own senderId.
  Future<void> sendSosResponse({
    required String alertId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String message,
  }) async {
    final alert = _firestore.collection('sos_alerts').doc(alertId);
    final batch = _firestore.batch();
    batch.set(alert.collection('responses').doc(), {
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(alert, {'status': 'acknowledged', 'acknowledgedBy': senderId});
    await batch.commit();
  }

  Future<void> stopPatientSos(String patientId) async {
    final alerts = await _firestore
        .collection('sos_alerts')
        .where('patientId', isEqualTo: patientId)
        .get();
    for (final alert in alerts.docs) {
      if (alert.data()['status'] == 'active') {
        await OfflineService.save(
          alert.reference.update({'status': 'stopped'}),
        );
      }
    }
  }

  /// One-shot lookup of family members linked to a patient. Uses a direct
  /// read (not a snapshot stream) so `triggerSos` can never hang waiting for
  /// the stream's first emission.
  Future<List<UserModel>> getFamilyLinkedToPatientOnce(String patientId) async {
    final snap = await _firestore
        .collection('users')
        .where('linkedPatientIds', arrayContains: patientId)
        .where('role', isEqualTo: 'family')
        .get();
    return snap.docs.map(_userFromDocument).toList();
  }

  /// Stream active SOS alerts where the current user is a recipient.
  ///
  /// Uses the composited (alertUserIds + status) query when available, but
  /// automatically falls back to a simpler query (array-contains only) if the
  /// composite index isn't deployed yet, filtering the status in Dart. This
  /// keeps the alert stream working for recipients without relying on manual
  /// index provisioning on the backend.
  Stream<List<SosAlert>> streamActiveSosAlertsForUser(String uid) {
    return Stream.fromFuture(_sosAlertsQuery(uid)).asyncExpand(
      (query) => query.snapshots().map(
        (snap) => snap.docs
            .map((d) => SosAlert.fromMap(d.id, d.data()))
            .where((a) => a.status == 'active')
            .toList(),
      ),
    );
  }

  Future<Query<Map<String, dynamic>>> _sosAlertsQuery(String uid) async {
    final base = _firestore
        .collection('sos_alerts')
        .where('alertUserIds', arrayContains: uid);
    try {
      final composite = base.where('status', isEqualTo: 'active');
      await composite.limit(1).get();
      return composite;
    } catch (_) {
      // Composite index not available; fall back to array-contains only and
      // let the caller filter active alerts in memory.
      return base;
    }
  }

  Future<void> acknowledgeSos(String alertId) async {
    await _firestore.collection('sos_alerts').doc(alertId).update({
      'status': 'acknowledged',
    });
  }

  Future<void> saveFcmToken(String uid, String token) async {
    if (token.isEmpty) return;
    await _firestore.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeFcmToken(String uid, String token) async {
    if (uid.isEmpty || token.isEmpty) return;
    final userRef = _firestore.collection('users').doc(uid);
    final updates = <String, Object>{
      'fcmTokens': FieldValue.arrayRemove([token]),
    };
    await userRef.update(updates);
  }

  // ==================== CHAT ====================

  Future<UserModel?> getUserById(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return _userFromDocument(doc);
  }

  Future<List<UserModel>> getChatContacts(String userId) async {
    _requireChatIdentity(userId);
    final me = await getUserById(userId);
    if (me == null) return [];
    switch (me.role) {
      case UserRole.patient:
        final contacts = <UserModel>[];
        if (me.caregiverId != null && me.caregiverId!.isNotEmpty) {
          final cg = await getUserById(me.caregiverId!);
          if (cg != null) contacts.add(cg);
        }
        final familySnap = await _firestore
            .collection('users')
            .where('linkedPatientIds', arrayContains: userId)
            .where('role', isEqualTo: 'family')
            .get();
        contacts.addAll(familySnap.docs.map(_userFromDocument));
        return contacts;
      case UserRole.caregiver:
        final snap = await _firestore
            .collection('users')
            .where('caregiverId', isEqualTo: userId)
            .get();
        return snap.docs.map(_userFromDocument).toList();
      case UserRole.family:
        final contacts = <UserModel>[];
        if (me.caregiverId != null && me.caregiverId!.isNotEmpty) {
          final cg = await getUserById(me.caregiverId!);
          if (cg != null) contacts.add(cg);
        }
        for (final pid in me.linkedPatientIds) {
          final p = await getUserById(pid);
          if (p != null) contacts.add(p);
        }
        return contacts;
      case UserRole.pharmacist:
        final contacts = <UserModel>[];
        if (me.caregiverId != null && me.caregiverId!.isNotEmpty) {
          final cg = await getUserById(me.caregiverId!);
          if (cg != null) contacts.add(cg);
        }
        return contacts;
    }
  }

  String _chatId(List<String> ids) {
    final sorted = ids.toList()..sort();
    return sorted.join('_');
  }

  /// Derive the deterministic chat room id for a pair of users without
  /// creating it. Guaranteed to match [findOrCreateChatRoom].
  String chatRoomIdFor(String myId, String otherId) {
    return _chatId([myId, otherId]);
  }

  Future<String> findOrCreateChatRoom(String myId, String otherId) async {
    _requireChatIdentity(myId);
    if (myId == otherId || otherId.isEmpty || otherId.contains('/')) {
      throw ArgumentError('Choose a valid chat partner.');
    }
    final id = _chatId([myId, otherId]);
    final room = _firestore.collection('chats').doc(id);
    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(room);
      if (doc.exists) return;
      transaction.set(room, {
        'participants': [myId, otherId],
        'lastMessage': '',
        'lastMessageSender': '',
        'lastMessageAt': DateTime.now().millisecondsSinceEpoch,
        'unreadCount': {myId: 0, otherId: 0},
      });
    });
    return id;
  }

  Stream<List<ChatRoom>> streamChatRooms(String userId) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => ChatRoom.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<ChatMessage>> streamMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
          final list = snap.docs
              .map(
                (d) => ChatMessage.fromMap(
                  d.id,
                  d.data(),
                  pending: d.metadata.hasPendingWrites,
                ),
              )
              .toList();
          // Safety net: always show messages old-to-new so replies stack below.
          list.sort((a, b) {
            final byTime = a.createdAt.compareTo(b.createdAt);
            if (byTime != 0) return byTime;
            return a.id.compareTo(b.id);
          });
          return list;
        });
  }

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String text,
    required String recipientId,
    String type = 'text',
    String? mediaUrl,
    String? caption,
    int? durationSeconds,
    bool forwarded = false,
  }) async {
    _requireChatIdentity(senderId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final room = _firestore.collection('chats').doc(chatId);
    final batch = _firestore.batch();
    batch.set(room.collection('messages').doc(), {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'createdAt': now,
      'type': type,
      'mediaUrl': ?mediaUrl,
      'caption': ?caption,
      'durationSeconds': ?durationSeconds,
      if (forwarded) 'forwarded': true,
    });
    batch.update(room, {
      'lastMessage': text.isNotEmpty
          ? text
          : (type == 'voice' ? 'Voice message' : 'Image'),
      'lastMessageSender': senderName,
      'lastMessageAt': now,
      'unreadCount.$recipientId': FieldValue.increment(1),
    });
    await OfflineService.save(batch.commit());
  }

  void _requireChatIdentity(String uid) {
    if (_sessionUid == null || _sessionUid != uid) {
      throw StateError('Your session has changed. Sign in again to use chat.');
    }
  }

  Stream<Map<String, dynamic>> chatPresence(String chatId) => _firestore
      .collection('chats')
      .doc(chatId)
      .collection('presence')
      .snapshots()
      .map((s) => {for (final d in s.docs) d.id: d.data()});

  Future<void> setTyping(String chatId, String uid, bool typing) =>
      OfflineService.save(
        _firestore
            .collection('chats')
            .doc(chatId)
            .collection('presence')
            .doc(uid)
            .set({
              'typingAt': typing ? DateTime.now().millisecondsSinceEpoch : 0,
            }, SetOptions(merge: true)),
      );

  Future<void> markChatRead(
    String chatId,
    String userId, {
    int? through,
  }) async {
    final room = _firestore.collection('chats').doc(chatId);
    final batch = _firestore.batch();
    batch.update(room, {'unreadCount.$userId': 0});
    if (through != null) {
      batch.set(room.collection('presence').doc(userId), {
        'readThrough': through,
      }, SetOptions(merge: true));
    }
    await OfflineService.save(batch.commit());
  }

  Future<void> incrementUnread(String chatId, String userId) async {
    await _firestore.collection('chats').doc(chatId).update({
      'unreadCount.$userId': FieldValue.increment(1),
    });
  }
}
