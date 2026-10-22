import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/medication_action.dart';
import 'caregiver_sqlite_service.dart';
import 'cloud_identity_service.dart';
import 'offline_service.dart';

/// SQLite is the single durable outbox for medication actions. Replays use the
/// same document ID, so interrupted acknowledgements never consume stock twice.
class MedicationActionSyncService {
  MedicationActionSyncService({
    CaregiverSqliteService? database,
    FirebaseFirestore? firestore,
    Connectivity? connectivity,
    Future<void> Function(MedicationAction action)? upload,
    String? Function()? currentUid,
    Stream<List<ConnectivityResult>>? connectivityChanges,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    Duration retryDelay = const Duration(seconds: 5),
  }) : _database = database ?? CaregiverSqliteService.instance,
       _firestore = firestore,
       _connectivity = connectivity ?? Connectivity(),
       _uploadOverride = upload,
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _changesOverride = connectivityChanges,
       _checkOverride = checkConnectivity,
       _retryDelay = retryDelay;

  static final instance = MedicationActionSyncService();
  final CaregiverSqliteService _database;
  final FirebaseFirestore? _firestore;
  final Connectivity _connectivity;
  final Future<void> Function(MedicationAction)? _uploadOverride;
  final String? Function() _currentUid;
  final Stream<List<ConnectivityResult>>? _changesOverride;
  final Future<List<ConnectivityResult>> Function()? _checkOverride;
  final Duration _retryDelay;
  late final _ids = CloudIdentityService(
    database: _database,
    firestore: _firestore,
  );
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<String>? _localSub;
  Timer? _retryTimer;
  String? _patientUid;
  int _generation = 0;
  bool _syncing = false;
  bool _requested = false;
  int _failures = 0;

  bool _active(String uid, int generation) =>
      _patientUid == uid && _generation == generation && _currentUid() == uid;

  Future<void> startForPatient(String patientUid) async {
    if (patientUid.trim().isEmpty || _currentUid() != patientUid) return;
    if (_patientUid != patientUid) {
      await stop();
      _patientUid = patientUid;
    }
    _connectivitySub ??=
        (_changesOverride ?? _connectivity.onConnectivityChanged).listen((
          state,
        ) {
          if (state.any((result) => result != ConnectivityResult.none)) {
            _retryTimer?.cancel();
            unawaited(syncPendingActions());
          }
        });
    _localSub ??= _database.medicationActionChanges
        .where((uid) => uid == patientUid)
        .listen((_) {
          unawaited(syncPendingActions());
        });
    try {
      final state =
          await (_checkOverride?.call() ?? _connectivity.checkConnectivity());
      if (state.any((result) => result != ConnectivityResult.none)) {
        await syncPendingActions();
      }
    } catch (_) {
      _scheduleRetry();
    }
  }

  Future<void> syncPendingActions() async {
    final patientUid = _patientUid;
    final generation = _generation;
    if (patientUid == null || !_active(patientUid, generation)) return;
    if (_syncing) {
      _requested = true;
      return;
    }
    _syncing = true;
    var failed = false;
    final rejected = <String>{};
    try {
      do {
        _requested = false;
        final pending = await _database.getPendingMedicationActions(patientUid);
        for (final action in pending) {
          if (!_active(patientUid, generation)) return;
          if (rejected.contains(action.id)) continue;
          try {
            await _upload(action).timeout(const Duration(seconds: 8));
            if (!_active(patientUid, generation)) return;
            await _database.setMedicationActionSyncStatus(action.id, 'synced');
          } catch (error) {
            if (_isRetryable(error)) rethrow;
            rejected.add(action.id);
            OfflineService.error.value =
                'A medication action is saved on this device and needs review before it can sync.';
          }
        }
      } while (_requested && _active(patientUid, generation));
      if (rejected.isNotEmpty) {
        _failures++;
        _scheduleRetry();
        return;
      }
      _failures = 0;
      _retryTimer?.cancel();
    } catch (error) {
      failed = true;
      if (_active(patientUid, generation)) {
        _failures++;
        if (!_isRetryable(error)) {
          OfflineService.error.value =
              'A medication action is saved on this device and could not sync. Please retry after checking the account.';
        }
        debugPrint('Medication action upload deferred (${error.runtimeType}).');
        _scheduleRetry();
      }
    } finally {
      _syncing = false;
      if (_requested && (!failed || generation != _generation)) {
        _requested = false;
        unawaited(syncPendingActions());
      }
    }
  }

  Future<void> _upload(MedicationAction action) async {
    if (_uploadOverride != null) return _uploadOverride(action);
    try {
      await _ids.writeAction(action.id, action.toMap());
    } on RecordIdCollision {
      await _database.rekeyMedicationAction(
        action.id,
        await _ids.nextId('medication_actions'),
      );
      rethrow;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_patientUid == null) return;
    final multiplier = 1 << (_failures > 6 ? 6 : _failures);
    final delay = Duration(
      milliseconds: (_retryDelay.inMilliseconds * multiplier).clamp(1, 300000),
    );
    _retryTimer = Timer(delay, () => unawaited(syncPendingActions()));
  }

  bool _isRetryable(Object error) =>
      error is TimeoutException ||
      error is RecordIdCollision ||
      error is FirebaseException &&
          const {
            'unavailable',
            'deadline-exceeded',
            'network-request-failed',
            'cancelled',
            'unknown',
          }.contains(error.code);

  Future<void> stop() async {
    _generation++;
    _patientUid = null;
    _requested = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _connectivitySub?.cancel();
    await _localSub?.cancel();
    _connectivitySub = null;
    _localSub = null;
    _failures = 0;
  }
}
