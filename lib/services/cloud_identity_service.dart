import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'caregiver_sqlite_service.dart';

class RecordIdCollision implements Exception {}

/// Account references are Firebase Auth UIDs. Clinical document paths are safe
/// integer IDs shared with SQLite; neither identity is duplicated in the body.
class CloudIdentityService {
  static final _random = Random.secure();
  CloudIdentityService({
    CaregiverSqliteService? database,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _database = database ?? CaregiverSqliteService.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _authOverride = auth;

  final CaregiverSqliteService _database;
  final FirebaseFirestore _firestore;
  final FirebaseAuth? _authOverride;
  late final _auth =
      _authOverride ?? FirebaseAuth.instanceFor(app: _firestore.app);
  late final _functions = FirebaseFunctions.instanceFor(
    app: _firestore.app,
    region: 'asia-southeast1',
  );
  String get _uid => _auth.currentUser?.uid ?? '';

  Future<Map<String, dynamic>> createProfile(
    Map<String, dynamic> profile,
  ) async {
    final owner = _uid;
    final result = await _functions
        .httpsCallable('saveAccountProfile')
        .call(profile);
    if (_uid != owner) throw StateError('The authenticated account changed.');
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> updateProfile(
    String uid,
    Map<String, dynamic> changes,
  ) async {
    final owner = _uid;
    final result = await _functions.httpsCallable('updateAccountProfile').call({
      'uid': uid,
      'changes': changes,
    });
    if (_uid != owner) throw StateError('The authenticated account changed.');
    final data = Map<String, dynamic>.from(result.data as Map);
    return Map<String, dynamic>.from(data['profile'] as Map);
  }

  Future<Map<String, dynamic>> createManagedProfile(
    Map<String, dynamic> profile,
    String password,
  ) async {
    final owner = _uid;
    void checkSession() {
      if (owner.isEmpty || _uid != owner) {
        throw StateError('The authenticated account changed.');
      }
    }

    checkSession();
    final requestId = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    // Snapshot the caller's lists too: a retry must represent the exact same
    // account request even if its form state changes while the network waits.
    final source = {...profile}..remove('uid');
    final payload = <String, dynamic>{
      ...Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map),
      'password': password,
      'requestId': requestId,
    };
    for (var attempt = 0; attempt < 3; attempt++) {
      checkSession();
      try {
        final result = await _functions
            .httpsCallable('createManagedAccount')
            .call(payload);
        checkSession();
        final data = Map<String, dynamic>.from(result.data as Map);
        return Map<String, dynamic>.from(data['profile'] as Map);
      } on FirebaseFunctionsException catch (error) {
        checkSession();
        if (attempt == 2 ||
            !const {
              'unavailable',
              'deadline-exceeded',
              'aborted',
            }.contains(error.code)) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
        checkSession();
      }
    }
    throw StateError('The account request could not be completed.');
  }

  Future<Map<String, dynamic>?> lookupUserByEmail(String email) async {
    final owner = _uid;
    final result = await _functions
        .httpsCallable(
          owner.isEmpty ? 'lookupCaregiverByEmail' : 'lookupUserByEmail',
        )
        .call({'email': email.trim().toLowerCase()});
    if (_uid != owner) throw StateError('The authenticated account changed.');
    final data = Map<String, dynamic>.from(result.data as Map);
    final profile = data['profile'];
    return profile == null ? null : Map<String, dynamic>.from(profile as Map);
  }

  Future<String> nextId(String entity) async =>
      (await _database.allocateOfflineRecordId(entity, _uid)).toString();

  static const _fields = {
    'medications': {
      'patientId',
      'caregiverId',
      'patientName',
      'name',
      'dosage',
      'time',
      'timeZone',
      'startDate',
      'intervalDays',
      'days',
      'type',
      'currentStock',
      'remindRefill',
      'remindThreshold',
      'imageUrl',
    },
    'appointments': {
      'patientId',
      'caregiverId',
      'patientName',
      'title',
      'date',
      'time',
      'location',
      'status',
      'remindBefore',
      'reminderViewedFor',
    },
    'medication_actions': {
      'patientId',
      'medicationId',
      'medicationName',
      'action',
      'timestamp',
      'snoozeUntil',
    },
    'moods': {
      'patientId',
      'moodIndex',
      'moodLabel',
      'emoji',
      'date',
      'timestamp',
    },
    'refill_requests': {
      'patientId',
      'caregiverId',
      'patientName',
      'caregiverName',
      'medicationId',
      'medicationName',
      'quantityLeft',
      'quantityRequested',
      'status',
      'requestedAt',
      'updatedAt',
      'pharmacyUid',
    },
  };

  /// A single boundary prevents local state or retired fields reaching Firebase.
  static Map<String, dynamic> encodeRecord(
    String entity,
    String key,
    Map<String, dynamic> source,
  ) {
    final id = int.tryParse(key);
    if (id == null || id <= 0 || id > 9007199254740991 || '$id' != key) {
      throw StateError('A canonical safe integer record ID is required.');
    }
    final fields = _fields[entity];
    if (fields == null) throw ArgumentError.value(entity, 'entity');
    final data = <String, dynamic>{
      for (final field in fields)
        if (source[field] != null) field: source[field],
    };
    for (final field in ['patientId', 'caregiverId']) {
      if (data.containsKey(field) &&
          (data[field] is! String || (data[field] as String).trim().isEmpty)) {
        throw StateError('$field must be a Firebase account UID.');
      }
    }
    if (data.containsKey('medicationId')) {
      final medicationId = int.tryParse(data['medicationId'].toString());
      if (medicationId == null ||
          medicationId <= 0 ||
          medicationId > 9007199254740991) {
        throw StateError('A safe integer medication ID is required.');
      }
      data['medicationId'] = medicationId;
    }
    return data;
  }

  Future<Map<String, dynamic>> encode(
    String entity,
    String key,
    Map<String, dynamic> source,
  ) async => encodeRecord(entity, key, source);

  Future<void> createRecord(
    String entity,
    String key,
    Map<String, dynamic> source,
  ) async {
    final owner = _uid;
    final data = encodeRecord(entity, key, source);
    final reference = _firestore.collection(entity).doc(key);
    await _firestore.runTransaction((transaction) async {
      if (_uid != owner) throw StateError('The authenticated account changed.');
      if ((await transaction.get(reference)).exists) throw RecordIdCollision();
      transaction.set(reference, data);
    });
  }

  /// An acknowledged retry of the same immutable action is a no-op. The first
  /// commit records the action and consumes one unit of stock atomically.
  Future<String> writeAction(String key, Map<String, dynamic> source) async {
    final owner = _uid;
    final data = encodeRecord('medication_actions', key, source);
    if (owner.isEmpty || data['patientId'] != owner) {
      throw StateError('Only the signed-in patient can upload this action.');
    }
    final reference = _firestore.collection('medication_actions').doc(key);
    await _firestore.runTransaction((transaction) async {
      if (_uid != owner) throw StateError('The authenticated account changed.');
      final existing = (await transaction.get(reference)).data();
      if (existing != null) {
        if (existing.length != data.length ||
            data.entries.any((entry) => existing[entry.key] != entry.value)) {
          throw RecordIdCollision();
        }
        return;
      }
      final medicationRef = _firestore
          .collection('medications')
          .doc('${data['medicationId']}');
      final medication = (await transaction.get(medicationRef)).data();
      if (_uid != owner) throw StateError('The authenticated account changed.');
      if (medication == null || medication['patientId'] != owner) {
        throw StateError('This medication is unavailable for this patient.');
      }
      final deletedAt = (medication['deletedAt'] as num?)?.toInt();
      if (deletedAt != null && (data['timestamp'] as int) > deletedAt) {
        throw StateError('This medication schedule has been deleted.');
      }
      transaction.set(reference, data);
      final stock = (medication['currentStock'] as num?)?.toInt() ?? 0;
      if (data['action'] == 'taken' &&
          stock > 0 &&
          medication['deletedAt'] == null) {
        transaction.update(medicationRef, {
          'currentStock': stock - 1,
          'lastActionId': key,
        });
      }
    });
    return key;
  }
}
