import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'caregiver_sqlite_service.dart';

class RecordIdCollision implements Exception {}

/// Integer IDs on both sides, lookups from clinical records, durable local IDs.
class CloudIdentityService {
  static bool aligned = true;
  CloudIdentityService({
    CaregiverSqliteService? database,
    FirebaseFirestore? firestore,
  }) : _database = database ?? CaregiverSqliteService.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;
  final CaregiverSqliteService _database;
  final FirebaseFirestore _firestore;
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> refreshMappings() async {
    final owner = _uid;
    try {
      final response = await _functions
          .httpsCallable(
            'getRecordIdentities',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 8)),
          )
          .call();
      if (owner != _uid) throw StateError('The authenticated account changed.');
      final data = Map<String, dynamic>.from(response.data as Map);
      final maps = <String, Map<String, int>>{};
      for (final entry in (data['mappings'] as Map).entries) {
        maps[entry.key as String] = Map<String, dynamic>.from(
          entry.value as Map,
        ).map((uid, id) => MapEntry(uid, (id as num).toInt()));
      }
      await _database.applyCloudIdMappings(maps);
    } on FirebaseFunctionsException catch (error) {
      if (!const {
        'unavailable',
        'deadline-exceeded',
        'internal',
        'cancelled',
      }.contains(error.code)) {
        rethrow;
      }
      // Existing SQLite aliases remain usable while disconnected.
    }
  }

  Future<Map<String, dynamic>> createProfile(
    Map<String, dynamic> profile,
  ) async {
    final result = await _functions
        .httpsCallable('saveAccountProfile')
        .call(profile);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> encodeProfileChanges(
    Map<String, dynamic> source,
  ) async {
    final result = <String, dynamic>{...source};
    final caregiver = source['caregiverId'];
    if (caregiver is String && caregiver.isNotEmpty) {
      result['caregiverId'] = await _userId(caregiver);
      result['caregiver_uid'] = caregiver;
    }
    final linked = source['linkedPatientIds'];
    if (linked is List<String>) {
      result['linkedPatientIds'] = await Future.wait(linked.map(_userId));
      result['linkedPatientUids'] = linked;
    }
    return result;
  }

  Future<String> nextId(String entity) async =>
      (await _database.allocateOfflineRecordId(entity, _uid)).toString();

  Future<int> _userId(String uid) async {
    final cached = await _database.cloudUserId(uid);
    if (cached != null) return cached;
    final document = await _firestore.collection('users').doc(uid).get();
    final id = document.data()?['id'];
    if (id is! int || id <= 0) {
      throw StateError('This account has no integer record ID.');
    }
    return id;
  }

  Future<Map<String, dynamic>> encode(
    String entity,
    String key,
    Map<String, dynamic> source,
  ) async {
    final id = int.tryParse(key);
    if (id == null || id <= 0 || id > 9007199254740991) {
      throw StateError('An integer record ID is required.');
    }
    final data = <String, dynamic>{...source, 'id': id, 'uid': key};
    for (final entry in const {
      'patientId': 'patient_uid',
      'caregiverId': 'caregiver_uid',
    }.entries) {
      final value = source[entry.value] ?? source[entry.key];
      if (value is! String || value.isEmpty) continue;
      data[entry.key] = await _userId(value);
      data[entry.value] = value;
    }
    if (source['medicationId'] != null) {
      final medicationId = int.tryParse(source['medicationId'].toString());
      if (medicationId == null || medicationId <= 0) {
        throw StateError('An integer medication ID is required.');
      }
      data['medicationId'] = medicationId;
      data['medication_uid'] = medicationId.toString();
    }
    return data;
  }

  Future<void> createRecord(
    String entity,
    String key,
    Map<String, dynamic> source,
  ) async {
    final data = await encode(entity, key, source);
    final reference = _firestore.collection(entity).doc(key);
    await _firestore.runTransaction((transaction) async {
      if ((await transaction.get(reference)).exists) throw RecordIdCollision();
      transaction.set(reference, data);
    });
  }

  /// SQLite owns offline queuing. Replays update the same action identity;
  /// collisions are re-keyed locally before any cloud overwrite can occur.
  Future<String> writeAction(String key, Map<String, dynamic> source) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final data = await encode('medication_actions', key, source);
      final reference = _firestore.collection('medication_actions').doc(key);
      try {
        await _firestore.runTransaction((transaction) async {
          final existing = (await transaction.get(reference)).data();
          if (existing != null &&
              (existing['patient_uid'] != data['patient_uid'] ||
                  existing['medicationId'] != data['medicationId'] ||
                  existing['timestamp'] != data['timestamp'])) {
            throw RecordIdCollision();
          }
          transaction.set(reference, data, SetOptions(merge: true));
        });
        return key;
      } on RecordIdCollision {
        final replacement = await nextId('medication_actions');
        await _database.applyCloudIdMappings({
          'medication_actions': {key: int.parse(replacement)},
        });
        key = replacement;
      }
    }
    throw StateError('Could not allocate a unique action ID.');
  }
}
