import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'offline_service.dart';
import 'sos_location_service.dart';
import 'local_profile_persistence_service.dart';
import 'caregiver_sqlite_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
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

class FirestoreService {
  FirestoreService({
    LocalProfilePersistenceService? localProfiles,
    CaregiverSqliteService? localDatabase,
  }) : _localProfiles = localProfiles ?? LocalProfilePersistenceService(),
       _localDatabase = localDatabase ?? CaregiverSqliteService.instance;

  final LocalProfilePersistenceService _localProfiles;
  final CaregiverSqliteService _localDatabase;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserModel _userFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) throw StateError('User profile is missing.');
    return UserModel.fromMap({...data, 'uid': document.id});
  }

  String get _apiKey => DefaultFirebaseOptions.currentPlatform.apiKey;

  static String _friendlyMessage(String code) {
    switch (code) {
      case 'CONFIGURATION_NOT_FOUND':
        return 'Email/Password sign-in is not enabled. Please contact support.';
      case 'EMAIL_EXISTS':
        return 'An account with this email already exists.';
      case 'OPERATION_NOT_ALLOWED':
        return 'Email/Password sign-in is not enabled.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Please try again later.';
      case 'EMAIL_NOT_FOUND':
        return 'No account found with this email.';
      case 'INVALID_PASSWORD':
        return 'Invalid password.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'INVALID_EMAIL':
        return 'Invalid email address.';
      case 'WEAK_PASSWORD':
        return 'Password should be at least 6 characters.';
      default:
        return code;
    }
  }

  Future<String> _createFirebaseUser(String email, String password) async {
    final response = await http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey',
      ),
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final message = body['error']['message'] ?? 'Failed to create account';
      throw Exception(_friendlyMessage(message));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['localId'] as String;
  }

  Future<UserModel?> getUserByEmail(String email) async {
    final snap = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return _userFromDocument(snap.docs.first);
  }

  Stream<List<UserModel>> getUsersByCaregiver(String caregiverId) {
    return _firestore
        .collection('users')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map(
          (snap) => snap.docs.map(_userFromDocument).toList(),
        );
  }

  Stream<List<UserModel>> getFamilyLinkedToPatient(String patientId) {
    return _firestore
        .collection('users')
        .where('linkedPatientIds', arrayContains: patientId)
        .snapshots()
        .map(
          (snap) => snap.docs.map(_userFromDocument).toList(),
        );
  }

  Stream<List<UserModel>> getPatientsByCaregiver(String caregiverId) {
    return _firestore
        .collection('users')
        .where('caregiverId', isEqualTo: caregiverId)
        .where('role', isEqualTo: 'patient')
        .snapshots()
        .map(
          (snap) => snap.docs.map(_userFromDocument).toList(),
        );
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
    final uid = await _createFirebaseUser(email, password);
    final now = DateTime.now();
    final birthDate = MalaysianIc.birthDate(icNumber);
    final dateOfBirth = birthDate == null
        ? null
        : '${birthDate.day.toString().padLeft(2, '0')}/'
              '${birthDate.month.toString().padLeft(2, '0')}/${birthDate.year}';
    final user = UserModel(
      uid: uid,
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
    await _firestore.collection('users').doc(uid).set(user.toMap());
    await _localProfiles.saveCreatedPatient(
      user.toMap(),
      caregiverUid: caregiverId,
    );
    return uid;
  }

  Future<String> createFamilyAccount({
    required String name,
    required String email,
    required String password,
    required String caregiverId,
    List<String> linkedPatientIds = const [],
    List<String> linkedPatientEmails = const [],
  }) async {
    final uid = await _createFirebaseUser(email, password);
    final user = UserModel(
      uid: uid,
      name: name,
      email: email,
      role: UserRole.family,
      createdAt: DateTime.now(),
      caregiverId: caregiverId,
      linkedPatientIds: linkedPatientIds,
      linkedPatientEmails: linkedPatientEmails,
      profilePicUrl: null,
      shortId: UserModel.generateId(UserRole.family),
    );
    await _firestore.collection('users').doc(uid).set(user.toMap());
    await _localProfiles.saveCreatedFamily(
      user.toMap(),
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
    final uid = await _createFirebaseUser(email, password);
    final user = UserModel(
      uid: uid,
      name: name,
      email: email,
      role: UserRole.pharmacist,
      createdAt: DateTime.now(),
      caregiverId: caregiverId,
      profilePicUrl: null,
      shortId: UserModel.generateId(UserRole.pharmacist),
    );
    await _firestore.collection('users').doc(uid).set(user.toMap());
    await _localProfiles.saveCreatedPharmacist(
      user.toMap(),
      caregiverUid: caregiverId,
    );
    return uid;
  }

  Future<String> createMedication(Medication medication) async {
    final doc = await _firestore
        .collection('medications')
        .add(medication.toMap());
    return doc.id;
  }

  Stream<List<Medication>> getMedicationsByCaregiver(String caregiverId) {
    return _firestore
        .collection('medications')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Medication.fromMap(d.id, d.data())).toList()
                ..sort(Medication.compareByTime),
        );
  }

  Stream<List<Medication>> getMedicationsByPatient(String patientId) {
    if (patientId.trim().isEmpty) return Stream.value(const []);
    final controller = StreamController<List<Medication>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
    var cancelled = false;
    var receivedServerSnapshot = false;
    Future<void> pendingCacheWrites = Future.value();
    List<Medication> localCache = const [];
    List<Medication> firestoreCache = const [];

    List<Medication> mergeCachedMedications() {
      final merged = <String, Medication>{
        for (final medication in localCache) medication.id: medication,
        for (final medication in firestoreCache) medication.id: medication,
      };
      return merged.values.toList()..sort(Medication.compareByTime);
    }

    Future<void> emitLocalCache() async {
      try {
        localCache = await _localDatabase.getCachedPatientMedications(
          patientId,
        );
        if (!cancelled && !receivedServerSnapshot && localCache.isNotEmpty) {
          controller.add(mergeCachedMedications());
        }
      } catch (_) {
        // Firebase remains usable when this device cannot open SQLite.
      }
    }

    controller.onListen = () {
      unawaited(emitLocalCache());
      try {
        subscription = _firestore
            .collection('medications')
            .where('patientId', isEqualTo: patientId)
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                late final List<Medication> medications;
                try {
                  medications = snapshot.docs
                      .where((doc) => doc.data()['patientId'] == patientId)
                      .map((doc) => Medication.fromMap(doc.id, doc.data()))
                      .toList()
                    ..sort(Medication.compareByTime);
                } catch (_) {
                  // A malformed server response cannot invalidate the cache.
                  return;
                }

                // Show usable Firestore cache results immediately, while
                // retaining SQLite rows until the server confirms the full
                // patient query. Metadata events ensure an identical server
                // result still becomes authoritative after a cached snapshot.
                if (snapshot.metadata.isFromCache ||
                    snapshot.metadata.hasPendingWrites) {
                  firestoreCache = medications;
                  if (!receivedServerSnapshot) {
                    final cached = mergeCachedMedications();
                    if (cached.isNotEmpty) controller.add(cached);
                  }
                  return;
                }

                receivedServerSnapshot = true;
                if (!cancelled) controller.add(medications);
                pendingCacheWrites = pendingCacheWrites.then((_) async {
                  try {
                    await _localDatabase.replacePatientMedicationCache(
                      patientId,
                      medications,
                    );
                  } catch (_) {
                    // Keep Firebase results available if SQLite is unavailable.
                  }
                });
              },
              onError: (Object _, StackTrace __) {
                // Keep the initial SQLite emission; a network error is not an
                // authoritative empty medication list.
              },
              onDone: () {
                if (!cancelled) controller.close();
              },
            );
      } catch (_) {
        // Keep the local stream alive with whatever cache was available.
      }
    };
    controller.onCancel = () async {
      cancelled = true;
      await subscription?.cancel();
    };
    return controller.stream;
  }

  Future<String> createAppointment(Appointment appointment) async {
    final doc = await _firestore
        .collection('appointments')
        .add(appointment.toMap());
    return doc.id;
  }

  Future<void> updateAppointment(Appointment appointment) {
    return _firestore
        .collection('appointments')
        .doc(appointment.id)
        .update(appointment.toMap());
  }

  Future<void> updateAppointmentStatus(String appointmentId, String status) {
    return OfflineService.save(
      _firestore.collection('appointments').doc(appointmentId).update({
        'status': status,
      }),
    );
  }

  Future<List<Appointment>> getAppointmentsByCaregiverOnce(
    String caregiverId,
  ) async {
    final snap = await _firestore
        .collection('appointments')
        .where('caregiverId', isEqualTo: caregiverId)
        .get();
    return snap.docs.map((d) => Appointment.fromMap(d.id, d.data())).toList();
  }

  Future<void> updateMedication(Medication medication) {
    return _firestore
        .collection('medications')
        .doc(medication.id)
        .update(medication.toMap());
  }

  Stream<List<Appointment>> getAppointmentsByCaregiver(String caregiverId) {
    return _firestore
        .collection('appointments')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Appointment.fromMap(d.id, d.data())).toList()
                ..sort((a, b) => a.date.compareTo(b.date)),
        );
  }

  Stream<List<Appointment>> getAppointmentsByPatient(String patientId) {
    if (patientId.trim().isEmpty) return Stream.value(const []);
    // Remove any appointment rows cached by older app versions. The patient
    // schedule is displayed from Firestore, while SQLite stores profile and
    // medication data only.
    unawaited(
      _localDatabase
          .clearCachedPatientAppointments(patientId)
          .catchError((Object _) {}),
    );
    return _firestore
        .collection('appointments')
        .where('patientId', isEqualTo: patientId)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => doc.data()['patientId'] == patientId)
              .map((doc) => Appointment.fromMap(doc.id, doc.data()))
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date)),
        );
  }

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
    final doc = await _firestore.collection('medications').add(med.toMap());
    return doc.id;
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    data.removeWhere((_, v) => v == null);
    if (data.isNotEmpty) {
      await _firestore.collection('users').doc(uid).update(data);
    }
  }

  Future<void> deleteUserField(String uid, String field) async {
    await _firestore.collection('users').doc(uid).update({
      field: FieldValue.delete(),
    });
  }

  Future<void> cleanNullFields(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final deletes = <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.value == null) {
        deletes[entry.key] = FieldValue.delete();
      }
    }
    if (deletes.isNotEmpty) {
      await _firestore.collection('users').doc(uid).update(deletes);
    }
  }

  Future<String> createRefillRequest(RefillRequest request) async {
    final doc = _firestore.collection('refill_requests').doc();
    final savedRequest = request.copyWith(id: doc.id, status: 'pending');
    // Firestore acknowledgement is required before the local insert.
    await doc.set(savedRequest.toMap());
    try {
      await _localDatabase.saveRefillRequest(savedRequest);
    } catch (error) {
      // The request is already server-confirmed; login sync will retry caching.
      debugPrint('Refill request saved remotely but local cache failed: $error');
    }
    return doc.id;
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
    return _firestore
        .collection('refill_requests')
        .orderBy('requestedAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .where(
          (snap) =>
              !snap.metadata.isFromCache && !snap.metadata.hasPendingWrites,
        )
        .map(
          (snap) => snap.docs
              .map((d) => RefillRequest.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Future<void> updateRefillRequestStatus(
    String requestId,
    String status,
  ) async {
    const statuses = {
      'pending',
      'processing',
      'ready_for_pickup',
      'collected',
      'completed', // Legacy equivalent retained for existing records.
      'rejected',
    };
    if (!statuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Unsupported refill status');
    }
    final ref = _firestore.collection('refill_requests').doc(requestId);
    final updateAt = DateTime.now().millisecondsSinceEpoch;
    final confirmedData = await _firestore
        .runTransaction<Map<String, dynamic>>((transaction) async {
          final snap = await transaction.get(ref);
          final data = snap.data();
          if (data == null) throw StateError('Refill request not found.');
          final oldStatus = data['status'] as String? ?? 'pending';
          final shouldRestock =
              (status == 'collected' || status == 'completed') &&
              oldStatus != 'collected' &&
              oldStatus != 'completed';
          if (shouldRestock) {
            final medicationId = data['medicationId'] as String?;
            final quantity =
                ((data['quantityRequested'] as num?) ?? 0).toInt();
            if (medicationId != null && quantity > 0) {
              final medicationRef = _firestore
                  .collection('medications')
                  .doc(medicationId);
              final medication = await transaction.get(medicationRef);
              if (medication.exists) {
                transaction.update(medicationRef, {
                  'currentStock': FieldValue.increment(quantity),
                });
              }
            }
          }
          transaction.update(ref, {
            'status': status,
            'updateAt': updateAt,
            'updatedAt': updateAt,
          });
          return {...data, 'status': status, 'updateAt': updateAt,
            'updatedAt': updateAt};
        });
    // Only persist a pharmacy status locally after the transaction is
    // acknowledged by Firestore.
    try {
      await _localDatabase.saveRefillRequest(
        RefillRequest.fromMap(requestId, confirmedData),
      );
    } catch (error) {
      // The pharmacy update succeeded in Firestore. The caregiver listener
      // will retry the local mirror when the confirmed snapshot arrives.
      debugPrint('Confirmed refill status could not be cached locally: $error');
    }
  }

  Future<void> logMedicationAction({
    required String medicationId,
    required String medicationName,
    required String patientId,
    required String action,
    int? snoozedUntil,
  }) async {
    final actions = _firestore.collection('medication_actions');
    final actionRecord = MedicationAction(
      id: actions.doc().id,
      medicationId: medicationId,
      medicationName: medicationName,
      patientId: patientId,
      action: action,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      snoozedUntil: snoozedUntil,
      syncStatus: 'pending',
    );
    await _localDatabase.saveMedicationAction(actionRecord);
    await _syncMedicationAction(actionRecord);
  }

  Future<void> _syncMedicationAction(MedicationAction action) async {
    final synced = action.copyWith(syncStatus: 'synced');
    final write = _firestore
        .collection('medication_actions')
        .doc(action.id)
        .set(synced.toMap());
    final confirmation = write.then<void>(
      (_) async {
        try {
          await _localDatabase.saveMedicationAction(synced);
        } catch (error) {
          OfflineService.error.value =
              'Medication action synced to Firebase but could not update the local record: $error';
        }
      },
      onError: (Object error, StackTrace stack) async {
        try {
          await _localDatabase.setMedicationActionSyncStatus(
            action.id,
            'pending',
          );
        } catch (_) {}
        if (!_isRetryableMedicationActionError(error)) {
          OfflineService.error.value =
              'Medication action is saved on this device but could not sync: $error';
        }
      },
    );
    // Firestore may hold this write until the device reconnects. Keep the
    // patient flow responsive; the attached confirmation updates SQLite when
    // the server eventually acknowledges the same document ID.
    await confirmation.timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  bool _isRetryableMedicationActionError(Object error) {
    if (error is TimeoutException) return true;
    if (error is FirebaseException) {
      return const {
        'unavailable',
        'deadline-exceeded',
        'network-request-failed',
        'cancelled',
        'unknown',
      }.contains(error.code);
    }
    return false;
  }

  Stream<List<MedicationAction>> getMedicationActionsByPatient(
    String patientId,
  ) {
    late final StreamController<List<MedicationAction>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? firestoreSub;
    StreamSubscription<String>? localSub;
    var cancelled = false;
    List<MedicationAction> remoteActions = const [];

    Future<void> emitMerged() async {
      if (cancelled) return;
      try {
        final localActions = await _localDatabase.getMedicationActions(
          patientId,
        );
        if (cancelled) return;
        final merged = <String, MedicationAction>{
          for (final action in localActions) action.id: action,
          for (final action in remoteActions) action.id: action,
        };
        final result = merged.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        controller.add(result);
      } catch (_) {
        if (!cancelled && remoteActions.isNotEmpty) {
          controller.add(remoteActions);
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
            .snapshots()
            .listen(
              (snapshot) async {
                remoteActions = snapshot.docs
                    .map((doc) {
                      final action = MedicationAction.fromMap(
                        doc.id,
                        doc.data(),
                      );
                      return action.copyWith(
                        syncStatus: doc.metadata.hasPendingWrites
                            ? 'pending'
                            : 'synced',
                      );
                    })
                    .toList();
                for (final doc in snapshot.docs) {
                  if (!doc.metadata.hasPendingWrites) {
                    final action = MedicationAction.fromMap(
                      doc.id,
                      doc.data(),
                    );
                    try {
                      await _localDatabase.saveMedicationAction(
                        action.copyWith(syncStatus: 'synced'),
                      );
                    } catch (_) {
                      // Firebase history remains available if SQLite is unavailable.
                    }
                  }
                }
                await emitMerged();
              },
              onError: (Object _, StackTrace __) => unawaited(emitMerged()),
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
      _patientRecords('medications', ids).map(
        (docs) => docs.map((d) => Medication.fromMap(d.id, d.data())).toList(),
      );

  Stream<List<Appointment>> getAppointmentsByPatients(
    List<String> patientIds,
  ) => _patientRecords('appointments', patientIds).map(
    (docs) => docs.map((d) => Appointment.fromMap(d.id, d.data())).toList(),
  );

  // Fan out every chunk; never silently drop patients after Firestore's limit.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _patientRecords(
    String collection,
    List<String> patientIds,
  ) {
    final ids = patientIds.toSet().toList();
    if (ids.isEmpty) return Stream.value([]);
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    final latest = <int, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    late StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    controller;
    final count = ids.length;
    controller = StreamController(
      onListen: () {
        for (var i = 0; i < count; i++) {
          final chunk = [ids[i]];
          subscriptions.add(
            _firestore
                .collection(collection)
                .where('patientId', whereIn: chunk)
                .snapshots()
                .listen((snapshot) {
                  latest[i] = snapshot.docs;
                  if (latest.length == count) {
                    controller.add(
                      latest.values.expand((docs) => docs).toList(),
                    );
                  }
                }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
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

  Future<void> updateMedicationStock(String medId, int stock) async {
    await OfflineService.save(
      _firestore.collection('medications').doc(medId).update({
        'currentStock': stock,
      }),
    );
  }

  Future<void> restockMedication(String medId, int amount) async {
    await _firestore.collection('medications').doc(medId).update({
      'currentStock': FieldValue.increment(amount),
    });
  }

  Future<void> deleteMedication(String medId) async {
    await _firestore.collection('medications').doc(medId).delete();
  }

  Future<void> deleteAppointment(String appointmentId) async {
    await _firestore.collection('appointments').doc(appointmentId).delete();
  }

  Future<void> saveMood({
    required String patientId,
    required int moodIndex,
    required String moodLabel,
    required String emoji,
    required String date,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final document = _firestore.collection('moods').doc();
    final mood = DailyMood(
      id: document.id,
      patientId: patientId,
      moodIndex: moodIndex,
      moodLabel: moodLabel,
      emoji: emoji,
      date: date,
      timestamp: timestamp,
    );
    // Await the Firestore write directly: its Future completes only after the
    // server acknowledges it. Never add an unconfirmed write to SQLite.
    await document.set(mood.toMap());
    await _localDatabase.saveMood(mood);
  }

  Stream<DailyMood?> getTodayMood(String patientId, String date) {
    return _firestore
        .collection('moods')
        .where('patientId', isEqualTo: patientId)
        .where('date', isEqualTo: date)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          final docs = snap.docs.toList()
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
    if (patientIds.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('moods')
        .where('patientId', whereIn: patientIds.take(30).toList())
        .where('date', isEqualTo: date)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => DailyMood.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Create an SOS alert broadcast to the patient's caregiver and linked family members.
  /// Returns the id of the created alert document.
  Future<String> triggerSos(
    UserModel patient, {
    String triggerSource = 'in_app',
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
          .then((location) => OfflineService.save(doc.update(location)))
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
      'fcmToken': token,
      'fcmTokens': FieldValue.arrayUnion([token]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeFcmToken(String uid, String token) async {
    if (uid.isEmpty || token.isEmpty) return;
    final userRef = _firestore.collection('users').doc(uid);
    final snapshot = await userRef.get();
    final updates = <String, Object>{
      'fcmTokens': FieldValue.arrayRemove([token]),
    };
    if (snapshot.data()?['fcmToken'] == token) {
      updates['fcmToken'] = FieldValue.delete();
    }
    await userRef.update(updates);
  }

  // ==================== CHAT ====================

  Future<UserModel?> getUserById(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return _userFromDocument(doc);
  }

  Future<List<UserModel>> getChatContacts(String userId) async {
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
            .get();
        contacts.addAll(
          familySnap.docs.map(_userFromDocument),
        );
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
    final id = _chatId([myId, otherId]);
    final doc = await _firestore.collection('chats').doc(id).get();
    if (doc.exists) return id;
    await _firestore.collection('chats').doc(id).set({
      'participants': [myId, otherId],
      'lastMessage': '',
      'lastMessageSender': '',
      'lastMessageAt': DateTime.now().millisecondsSinceEpoch,
      'unreadCount': {myId: 0, otherId: 0},
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
