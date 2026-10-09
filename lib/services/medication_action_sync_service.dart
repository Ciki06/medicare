import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/medication_action.dart';
import 'caregiver_sqlite_service.dart';
import 'offline_service.dart';

/// Retries locally queued medication actions for the currently signed-in patient.
class MedicationActionSyncService {
  MedicationActionSyncService({
    CaregiverSqliteService? database,
    FirebaseFirestore? firestore,
    Connectivity? connectivity,
  }) : _database = database ?? CaregiverSqliteService.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _connectivity = connectivity ?? Connectivity();

  static final instance = MedicationActionSyncService();

  final CaregiverSqliteService _database;
  final FirebaseFirestore _firestore;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  String? _patientUid;
  bool _syncing = false;
  bool _syncRequestedWhileRunning = false;

  Future<void> startForPatient(String patientUid) async {
    if (patientUid.trim().isEmpty) return;
    if (_patientUid != patientUid) {
      await stop();
      _patientUid = patientUid;
    }
    _connectivitySub ??= _connectivity.onConnectivityChanged.listen((state) {
      if (state.any((result) => result != ConnectivityResult.none)) {
        unawaited(syncPendingActions());
      }
    });
    try {
      final state = await _connectivity.checkConnectivity();
      if (state.any((result) => result != ConnectivityResult.none)) {
        await syncPendingActions();
      }
    } catch (error) {
      debugPrint('Could not check connectivity for medication sync: $error');
    }
  }

  Future<void> syncPendingActions() async {
    final patientUid = _patientUid;
    if (patientUid == null) return;
    if (_syncing) {
      _syncRequestedWhileRunning = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncRequestedWhileRunning = false;
        final pending = await _database.getPendingMedicationActions(patientUid);
        for (final action in pending) {
          if (_patientUid != patientUid) return;
          final completed = await _syncOne(action);
          if (!completed) break;
        }
      } while (_syncRequestedWhileRunning && _patientUid == patientUid);
    } catch (error) {
      debugPrint('Medication action retry was deferred: $error');
    } finally {
      _syncing = false;
    }
  }

  Future<bool> _syncOne(MedicationAction action) async {
    final synced = action.copyWith(syncStatus: 'synced');
    final write = _firestore
        .collection('medication_actions')
        .doc(action.id)
        .set(synced.toMap())
        .then<void>(
          (_) async {
            try {
              await _database.saveMedicationAction(synced);
            } catch (error) {
              debugPrint(
                'Synced medication action remains locally pending: $error',
              );
            }
          },
          onError: (Object error, StackTrace stack) async {
            try {
              await _database.setMedicationActionSyncStatus(
                action.id,
                'pending',
              );
            } catch (_) {}
          },
        );
    try {
      await write.timeout(const Duration(seconds: 8));
      return true;
    } on TimeoutException {
      // The write may still be queued by Firestore. Its completion handler
      // marks the same local action synced if the server later acknowledges it.
      return false;
    } catch (error) {
      await _database.setMedicationActionSyncStatus(action.id, 'pending');
      if (!_isRetryable(error)) {
        OfflineService.error.value =
            'Medication action is saved on this device but could not sync: $error';
      }
      debugPrint('Medication action remains pending: $error');
      return false;
    }
  }

  bool _isRetryable(Object error) {
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

  Future<void> stop() async {
    _patientUid = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }
}
