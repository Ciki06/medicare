import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/refill_request.dart';
import 'caregiver_sqlite_service.dart';

/// Keeps a caregiver's confirmed refill request history mirrored locally.
class RefillRequestSyncService {
  RefillRequestSyncService({
    FirebaseFirestore? firestore,
    CaregiverSqliteService? database,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _database = database ?? CaregiverSqliteService.instance;

  static final instance = RefillRequestSyncService();

  final FirebaseFirestore _firestore;
  final CaregiverSqliteService _database;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _caregiverId;
  String? _sessionUid;
  int _generation = 0;
  Timer? _retryTimer;
  Future<void> _cacheWrites = Future.value();

  Future<void> startForCaregiver(String caregiverId) async {
    if (caregiverId.trim().isEmpty) return;
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner == null) return;
    if (_caregiverId == caregiverId &&
        _sessionUid == owner &&
        _subscription != null) {
      return;
    }
    await stop();
    _caregiverId = caregiverId;
    _sessionUid = owner;
    final generation = _generation;
    _subscription = _firestore
        .collection('refill_requests')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            // Cache snapshots and optimistic local writes are not confirmed
            // server state. Wait for Firestore's acknowledged snapshot.
            if (snapshot.metadata.isFromCache ||
                snapshot.metadata.hasPendingWrites ||
                _caregiverId != caregiverId ||
                _generation != generation ||
                FirebaseAuth.instance.currentUser?.uid != owner) {
              return;
            }
            final requests = snapshot.docs
                .map((doc) => RefillRequest.fromMap(doc.id, doc.data()))
                .toList();
            _cacheWrites = _cacheWrites.then((_) async {
              if (_caregiverId == caregiverId &&
                  _generation == generation &&
                  FirebaseAuth.instance.currentUser?.uid == owner) {
                await _persistSnapshot(caregiverId, requests);
              }
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Refill request sync failed for $caregiverId: $error');
            if (_generation != generation) return;
            final subscription = _subscription;
            _subscription = null;
            unawaited(subscription?.cancel());
            _retryTimer?.cancel();
            _retryTimer = Timer(const Duration(seconds: 5), () {
              if (_caregiverId == caregiverId && _generation == generation) {
                unawaited(startForCaregiver(caregiverId));
              }
            });
          },
        );
  }

  Future<void> _persistSnapshot(
    String caregiverId,
    List<RefillRequest> requests,
  ) async {
    try {
      await _database.syncRefillRequests(caregiverId, requests);
    } catch (error) {
      debugPrint('Could not cache refill requests for $caregiverId: $error');
    }
  }

  Future<void> stop() async {
    _generation++;
    _caregiverId = null;
    _sessionUid = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
