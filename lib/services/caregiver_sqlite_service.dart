import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/local_caregiver_record.dart';
import '../models/local_patient_record.dart';
import '../models/medication_action.dart';
import '../models/medication_model.dart';
import '../models/mood_model.dart';
import '../models/refill_request.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import 'clinical_local_schema.dart';
import 'integer_record_id.dart';
import 'local_id_schema.dart';

/// Owns the shared device cache and durable medication-action outbox.
class CaregiverSqliteService {
  CaregiverSqliteService({DatabaseFactory? factory, String? databasePath})
    : _factory = factory,
      _databasePath = databasePath;

  static final instance = CaregiverSqliteService();
  final DatabaseFactory? _factory;
  final String? _databasePath;
  final Map<String, Set<int>> _issuedIds = {};
  Future<Database>? _opening;
  final _medicationActionChanges = StreamController<String>.broadcast(
    sync: true,
  );
  final _refillRequestChanges = StreamController<String>.broadcast(sync: true);

  Stream<String> get medicationActionChanges => _medicationActionChanges.stream;
  Stream<String> get refillRequestChanges => _refillRequestChanges.stream;
  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    try {
      final (factory, path) = _factory != null && _databasePath != null
          ? (_factory, _databasePath)
          : await _mobileDatabaseLocation();
      return await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: ClinicalLocalSchema.version,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) => ClinicalLocalSchema.create(db),
          // This release starts a separate database. Old databases stay untouched.
          onUpgrade: (_, _, _) =>
              throw StateError('Use the fresh v18 database.'),
        ),
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<int?> _profileId(
    DatabaseExecutor db,
    String table,
    String key,
    String uid,
  ) async {
    final rows = await db.query(
      table,
      columns: [key],
      where: 'uid=?',
      whereArgs: [uid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single[key] as int;
  }

  /// A UID-only cache entry is sufficient for a clinical FK. A later confirmed
  /// profile updates this same row; it does not invent a cloud account.
  static Future<int> _patientId(DatabaseExecutor db, String uid) async {
    if (uid.trim().isEmpty) throw ArgumentError('A patient UID is required.');
    final existing = await _profileId(db, 'Patients', 'patient_id', uid);
    if (existing != null) return existing;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('Patients', {
      'uid': uid,
      'created_at': now,
      'updated_at': now,
    });
  }

  // Identity rows survive schedule refreshes so history and refill foreign keys stay valid.
  static Future<void> _parent(
    DatabaseExecutor db,
    String table,
    String key,
    int id,
  ) async {
    await db.insert(table, {
      key: id,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // Profiles can arrive after schedules; resolve those stored UIDs to the new local key.
  static Future<void> _backfillCaregiver(
    DatabaseExecutor db,
    String uid,
    int id,
  ) async {
    for (final table in const [
      'Patients',
      'Family_members',
      'Pharmacists',
      'Medication_Schedule',
      'Appointment_Schedules',
      'Refill_Request',
    ]) {
      await db.update(
        table,
        {'caregiver_id': id},
        where: 'caregiver_uid=?',
        whereArgs: [uid],
      );
    }
  }

  Future<void> saveRefillRequest(RefillRequest request) async {
    if (request.caregiverId.trim().isEmpty ||
        request.patientId.trim().isEmpty) {
      throw ArgumentError('Invalid refill request.');
    }
    final db = await database;
    await db.transaction((txn) => _storeRefillRequest(txn, request));
    _refillRequestChanges.add(request.caregiverId);
  }

  static Future<void> _storeRefillRequest(
    DatabaseExecutor db,
    RefillRequest request,
  ) async {
    final id = LocalIdSchema.requireId(request.id);
    final medicationId = LocalIdSchema.requireId(request.medicationId);
    final patientId = await _patientId(db, request.patientId);
    final caregiverId = await _profileId(
      db,
      'Caregivers',
      'caregiver_id',
      request.caregiverId,
    );
    final pharmacyUid = request.pharmacyUid;
    final pharmacyId = pharmacyUid == null
        ? null
        : await _profileId(db, 'Pharmacists', 'pharmacy_id', pharmacyUid);
    await _parent(db, 'Medications', 'medication_id', medicationId);
    final row = <String, Object?>{
      'id': id,
      'caregiver_id': caregiverId,
      'caregiver_uid': request.caregiverId,
      'pharmacy_id': pharmacyId,
      'pharmacy_uid': pharmacyUid,
      'patient_id': patientId,
      'medication_id': medicationId,
      'caregiver_name': request.caregiverName,
      'patient_name': request.patientName,
      'medication_name': request.medicationName,
      'quantity_left': request.quantityLeft,
      'quantity_requested': request.quantityRequested,
      'status': request.status,
      'requested_at': request.requestedAt,
      'updated_at': request.updatedAt,
    };
    final existing = await db.query(
      'Refill_Request',
      columns: [
        'patient_id',
        'medication_id',
        'caregiver_uid',
        'requested_at',
        'updated_at',
      ],
      where: 'id=?',
      whereArgs: [id],
    );
    if (existing.isEmpty) {
      await db.insert('Refill_Request', row);
    } else {
      if (existing.single['patient_id'] != patientId ||
          existing.single['medication_id'] != medicationId ||
          existing.single['caregiver_uid'] != request.caregiverId) {
        throw StateError(
          'A refill identity cannot be assigned to another record.',
        );
      }
      // Ignore delayed snapshots that would move an already cached refill backward.
      final currentVersion =
          (existing.single['updated_at'] ?? existing.single['requested_at'])
              as int;
      if ((request.updatedAt ?? request.requestedAt) < currentVersion) return;
      await db.update('Refill_Request', row, where: 'id=?', whereArgs: [id]);
    }
  }

  /// Applies a complete server-confirmed snapshot atomically, including remote
  /// deletions. Refill writes are acknowledged cloud operations; SQLite mirrors
  /// their confirmed state without maintaining a second upload queue.
  Future<void> syncRefillRequests(
    String caregiverId,
    List<RefillRequest> requests,
  ) async {
    if (caregiverId.trim().isEmpty ||
        requests.any((request) => request.caregiverId != caregiverId)) {
      throw ArgumentError('Refill request sync is restricted to a caregiver.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final ids = requests
          .map((request) => LocalIdSchema.requireId(request.id))
          .toSet();
      for (final request in requests) {
        await _storeRefillRequest(txn, request);
      }
      final existing = await txn.query(
        'Refill_Request',
        columns: ['id'],
        where: 'caregiver_uid=?',
        whereArgs: [caregiverId],
      );
      for (final row in existing) {
        if (!ids.contains(row['id'])) {
          await txn.delete(
            'Refill_Request',
            where: 'id=?',
            whereArgs: [row['id']],
          );
        }
      }
    });
    _refillRequestChanges.add(caregiverId);
  }

  Future<List<RefillRequest>> getRefillRequests(String caregiverId) async {
    if (caregiverId.trim().isEmpty) return [];
    final rows = await (await database).rawQuery(
      '''
      SELECT r.*, p.uid AS patient_uid FROM Refill_Request r
      JOIN Patients p ON p.patient_id=r.patient_id
      WHERE r.caregiver_uid=? ORDER BY r.requested_at DESC, r.id DESC
    ''',
      [caregiverId],
    );
    return rows
        .map(
          (row) => RefillRequest.fromMap(row['id'].toString(), {
            'caregiverId': row['caregiver_uid'],
            'caregiverName': row['caregiver_name'],
            'patientId': row['patient_uid'],
            'patientName': row['patient_name'],
            'medicationId': row['medication_id'],
            'medicationName': row['medication_name'],
            'pharmacyUid': row['pharmacy_uid'],
            'quantityLeft': row['quantity_left'],
            'quantityRequested': row['quantity_requested'],
            'status': row['status'],
            'requestedAt': row['requested_at'],
            'updatedAt': row['updated_at'],
          }).copyWith(pharmacyId: row['pharmacy_id'] as int?),
        )
        .toList();
  }

  Stream<List<RefillRequest>> watchRefillRequests(String caregiverId) {
    late final StreamController<List<RefillRequest>> controller;
    StreamSubscription<String>? changes;
    var cancelled = false;
    Future<void> emit() async {
      try {
        final requests = await getRefillRequests(caregiverId);
        if (!cancelled) controller.add(requests);
      } catch (error, stackTrace) {
        if (!cancelled) controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<List<RefillRequest>>(
      onListen: () {
        changes = refillRequestChanges
            .where((id) => id == caregiverId)
            .listen((_) => unawaited(emit()));
        unawaited(emit());
      },
      onCancel: () async {
        cancelled = true;
        await changes?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> saveMood(DailyMood mood) async {
    final db = await database;
    await db.transaction((txn) => _storeMood(txn, mood));
  }

  static Future<void> _storeMood(DatabaseExecutor db, DailyMood mood) async {
    final id = LocalIdSchema.requireId(mood.id);
    final patientId = await _patientId(db, mood.patientId);
    final existing = await db.query(
      'Mood',
      columns: ['patient_id', 'timestamp'],
      where: 'id=?',
      whereArgs: [id],
    );
    if (existing.isNotEmpty && existing.single['patient_id'] != patientId) {
      throw StateError(
        'A mood identity cannot be assigned to another patient.',
      );
    }
    if (existing.isNotEmpty &&
        (existing.single['timestamp'] as int) > mood.timestamp) {
      return;
    }
    final row = <String, Object?>{
      'id': id,
      'patient_id': patientId,
      'mood_index': mood.moodIndex,
      'mood_label': mood.moodLabel,
      'emoji': mood.emoji,
      'date': mood.date,
      'timestamp': mood.timestamp,
    };
    if (existing.isEmpty) {
      await db.insert('Mood', row);
    } else {
      await db.update('Mood', row, where: 'id=?', whereArgs: [id]);
    }
  }

  Future<void> replacePatientMoodCache(
    String patientUid,
    List<DailyMood> moods,
  ) async {
    if (patientUid.trim().isEmpty ||
        moods.any((mood) => mood.patientId != patientUid)) {
      throw StateError('Mood cache is restricted to the requested patient.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final patientId = await _patientId(txn, patientUid);
      final retained = moods
          .map((mood) => LocalIdSchema.requireId(mood.id))
          .toSet();
      for (final mood in moods) {
        await _storeMood(txn, mood);
      }
      for (final row in await txn.query(
        'Mood',
        columns: ['id'],
        where: 'patient_id=?',
        whereArgs: [patientId],
      )) {
        if (!retained.contains(row['id'])) {
          await txn.delete('Mood', where: 'id=?', whereArgs: [row['id']]);
        }
      }
    });
  }

  Future<void> deleteMood(String id) async {
    if (id.isEmpty) return;
    await (await database).delete(
      'Mood',
      where: 'id=?',
      whereArgs: [LocalIdSchema.requireId(id)],
    );
  }

  Future<List<Medication>> getCachedPatientMedications(
    String patientUid,
  ) async {
    if (patientUid.trim().isEmpty) {
      throw ArgumentError('A patient UID is required.');
    }
    final rows = await (await database).rawQuery(
      '''
      SELECT s.* FROM Medication_Schedule s JOIN Patients p ON p.patient_id=s.patient_id
      WHERE p.uid=? ORDER BY s.time, s.medication_id
    ''',
      [patientUid],
    );
    return rows
        .map(
          (row) => Medication.fromMap(row['medication_id'].toString(), {
            'caregiverId': row['caregiver_uid'],
            'patientId': patientUid,
            'patientName': row['patient_name'],
            'name': row['name'],
            'type': row['type'],
            'currentStock': row['current_stock'],
            'days': jsonDecode(row['days_json'] as String),
            'dosage': row['dosage'],
            'imageUrl': row['image_url'],
            'intervalDays': row['interval_days'],
            'remindRefill': row['remind_refill'] == 1,
            'remindThreshold': row['remind_threshold'],
            'startDate': row['start_date'],
            'time': row['time'],
            'timeZone': row['timezone'],
          }),
        )
        .toList();
  }

  /// Replace a single patient's cache only with a complete server-confirmed
  /// snapshot. Invalid records roll back the entire refresh.
  Future<void> replacePatientMedicationCache(
    String patientUid,
    List<Medication> medications,
  ) async {
    if (patientUid.trim().isEmpty ||
        medications.any((medication) => medication.patientId != patientUid)) {
      throw StateError(
        'Medication cache is restricted to the requested patient.',
      );
    }
    final db = await database;
    await db.transaction((txn) async {
      final patientId = await _profileId(
        txn,
        'Patients',
        'patient_id',
        patientUid,
      );
      if (patientId == null) return;
      await txn.delete(
        'Medication_Schedule',
        where: 'patient_id=?',
        whereArgs: [patientId],
      );
      for (final medication in medications) {
        final id = LocalIdSchema.requireId(medication.id);
        await _parent(txn, 'Medications', 'medication_id', id);
        await txn.insert('Medication_Schedule', {
          'patient_id': patientId,
          'medication_id': id,
          'caregiver_id': await _profileId(
            txn,
            'Caregivers',
            'caregiver_id',
            medication.caregiverId,
          ),
          'caregiver_uid': medication.caregiverId,
          'patient_name': medication.patientName,
          'name': medication.name,
          'type': medication.type,
          'days_json': jsonEncode(medication.days),
          'dosage': medication.dosage,
          'time': medication.time,
          'timezone': medication.timeZone,
          'start_date': medication.startDate,
          'remind_refill': medication.remindRefill ? 1 : 0,
          'remind_threshold': medication.remindThreshold,
          'current_stock': medication.currentStock,
          'interval_days': medication.intervalDays,
          'image_url': medication.imageUrl,
        });
      }
    });
  }

  Future<List<Appointment>> getCachedPatientAppointments(
    String patientUid,
  ) async {
    if (patientUid.trim().isEmpty) {
      throw ArgumentError('A patient UID is required.');
    }
    final rows = await (await database).rawQuery(
      '''
      SELECT s.* FROM Appointment_Schedules s JOIN Patients p ON p.patient_id=s.patient_id
      WHERE p.uid=? ORDER BY s.date, s.time, s.appointment_id
    ''',
      [patientUid],
    );
    return rows
        .map(
          (row) => Appointment.fromMap(row['appointment_id'].toString(), {
            'caregiverId': row['caregiver_uid'],
            'patientId': patientUid,
            'patientName': row['patient_name'],
            'date': row['date'],
            'time': row['time'],
            'location': row['location'],
            'title': row['title'],
            'status': row['status'],
            'remindBefore': row['remind_before'],
          }),
        )
        .toList();
  }

  Future<void> replacePatientAppointmentCache(
    String patientUid,
    List<Appointment> appointments,
  ) async {
    if (patientUid.trim().isEmpty ||
        appointments.any(
          (appointment) => appointment.patientId != patientUid,
        )) {
      throw StateError(
        'Appointment cache is restricted to the requested patient.',
      );
    }
    final db = await database;
    await db.transaction((txn) async {
      final patientId = await _profileId(
        txn,
        'Patients',
        'patient_id',
        patientUid,
      );
      if (patientId == null) return;
      await txn.delete(
        'Appointment_Schedules',
        where: 'patient_id=?',
        whereArgs: [patientId],
      );
      for (final appointment in appointments) {
        final id = LocalIdSchema.requireId(appointment.id);
        await _parent(txn, 'Appointments', 'appointment_id', id);
        await txn.insert('Appointment_Schedules', {
          'patient_id': patientId,
          'appointment_id': id,
          'caregiver_id': await _profileId(
            txn,
            'Caregivers',
            'caregiver_id',
            appointment.caregiverId,
          ),
          'caregiver_uid': appointment.caregiverId,
          'patient_name': appointment.patientName,
          'title': appointment.title,
          'date': appointment.date,
          'time': appointment.time,
          'location': appointment.location,
          'remind_before': appointment.remindBefore,
          'status': appointment.status,
        });
      }
    });
  }

  Future<void> saveMedicationAction(
    MedicationAction action, {
    String? syncStatus,
    bool preservePending = false,
  }) async {
    final id = LocalIdSchema.requireId(action.id);
    final medicationId = LocalIdSchema.requireId(action.medicationId);
    final status = syncStatus ?? action.syncStatus;
    if (!['taken', 'skipped', 'snoozed'].contains(action.action) ||
        !['pending', 'synced'].contains(status)) {
      throw ArgumentError('Invalid medication action record.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final patientId = await _patientId(txn, action.patientId);
      await _parent(txn, 'Medications', 'medication_id', medicationId);
      final existing = await txn.query(
        'Medication_Action',
        where: 'id=?',
        whereArgs: [id],
      );
      if (existing.isNotEmpty) {
        if (existing.single['patient_id'] != patientId ||
            existing.single['medication_id'] != medicationId ||
            existing.single['timestamp'] != action.timestamp ||
            existing.single['action'] != action.action ||
            existing.single['snooze_until'] != action.snoozedUntil) {
          throw StateError(
            'A medication action identity cannot be reassigned.',
          );
        }
        // Downloaded history must not mark a pending local action as uploaded.
        if (status == 'pending' ||
            (preservePending && existing.single['sync_status'] == 'pending')) {
          return;
        }
      }
      final row = <String, Object?>{
        'id': id,
        'medication_id': medicationId,
        'medication_name': action.medicationName,
        'patient_id': patientId,
        'action': action.action,
        'timestamp': action.timestamp,
        'snooze_until': action.snoozedUntil,
        'sync_status': status,
      };
      if (existing.isEmpty) {
        await txn.insert('Medication_Action', row);
      } else {
        await txn.update(
          'Medication_Action',
          row,
          where: 'id=?',
          whereArgs: [id],
        );
      }
    });
    _medicationActionChanges.add(action.patientId);
  }

  Future<void> setMedicationActionSyncStatus(String id, String status) async {
    final key = LocalIdSchema.requireId(id);
    if (!['pending', 'synced'].contains(status)) {
      throw ArgumentError('Invalid action sync state.');
    }
    final db = await database;
    final uid = await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT p.uid FROM Medication_Action a JOIN Patients p ON p.patient_id=a.patient_id WHERE a.id=?',
        [key],
      );
      await txn.update(
        'Medication_Action',
        {'sync_status': status},
        where: 'id=?',
        whereArgs: [key],
      );
      return rows.isEmpty ? null : rows.single['uid'] as String;
    });
    if (uid != null) _medicationActionChanges.add(uid);
  }

  Future<List<MedicationAction>> _readMedicationActions(
    String patientUid, {
    bool pendingOnly = false,
  }) async {
    if (patientUid.trim().isEmpty) return [];
    final rows = await (await database).rawQuery(
      '''
      SELECT a.* FROM Medication_Action a JOIN Patients p ON p.patient_id=a.patient_id
      WHERE p.uid=? ${pendingOnly ? "AND a.sync_status='pending'" : ''}
      ORDER BY a.timestamp ${pendingOnly ? 'ASC' : 'DESC'}, a.id ${pendingOnly ? 'ASC' : 'DESC'}
    ''',
      [patientUid],
    );
    return rows
        .map(
          (row) => MedicationAction.fromMap(row['id'].toString(), {
            'patientId': patientUid,
            'medicationId': row['medication_id'],
            'medicationName': row['medication_name'],
            'action': row['action'],
            'timestamp': row['timestamp'],
            'snoozeUntil': row['snooze_until'],
            'syncStatus': row['sync_status'],
          }),
        )
        .toList();
  }

  Future<List<MedicationAction>> getMedicationActions(String patientUid) =>
      _readMedicationActions(patientUid);
  Future<List<MedicationAction>> getPendingMedicationActions(
    String patientUid,
  ) => _readMedicationActions(patientUid, pendingOnly: true);

  Future<void> rekeyMedicationAction(String oldKey, String newKey) async {
    final oldId = LocalIdSchema.requireId(oldKey),
        nextId = LocalIdSchema.requireId(newKey);
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'Medication_Action',
        where: 'id=? AND sync_status=?',
        whereArgs: [oldId, 'pending'],
      );
      if (rows.isEmpty) {
        throw StateError('Only an unsent action can change its ID.');
      }
      await txn.update(
        'Medication_Action',
        {'id': nextId},
        where: 'id=?',
        whereArgs: [oldId],
      );
    });
  }

  Future<Map<String, Object?>?> getPharmacist(String uid) async {
    if (uid.trim().isEmpty) throw ArgumentError('Firebase UID is required.');
    final rows = await (await database).query(
      'pharmacists',
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> savePharmacist(
    String uid,
    Map<String, dynamic> profile, {
    bool authoritative = false,
  }) async {
    if (uid.trim().isEmpty ||
        profile['uid'] != uid ||
        profile['role'] != 'pharmacist') {
      throw StateError(
        'Only the authenticated pharmacist profile can be saved.',
      );
    }
    final values = <String, Object?>{};
    for (final field in const ['name', 'phone', 'email']) {
      final value = profile[field];
      if (value != null && value is! String) {
        throw ArgumentError('Invalid pharmacist profile field.');
      }
      if (authoritative) {
        values[field] = value is String && value.trim().isNotEmpty
            ? value.trim()
            : null;
      } else if (value is String && value.trim().isNotEmpty) {
        values[field] = value.trim();
      }
    }
    final caregiverUid = profile['caregiverId'];
    if (caregiverUid != null && caregiverUid is! String) {
      throw ArgumentError('Invalid caregiver UID.');
    }
    if (caregiverUid is String && caregiverUid.trim().isNotEmpty) {
      values['caregiver_uid'] = caregiverUid.trim();
    }
    final db = await database;
    await db.transaction((txn) async {
      if ((authoritative || profile.containsKey('caregiverId')) &&
          caregiverUid == null) {
        values['caregiver_uid'] = null;
        values['caregiver_id'] = null;
      }
      if (caregiverUid is String && caregiverUid.trim().isNotEmpty) {
        values['caregiver_id'] = await _profileId(
          txn,
          'Caregivers',
          'caregiver_id',
          caregiverUid.trim(),
        );
      }
      final rows = await txn.query(
        'pharmacists',
        where: 'uid = ?',
        whereArgs: [uid],
        limit: 1,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      if (rows.isEmpty) {
        await txn.insert('pharmacists', {
          'uid': uid,
          ...values,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        await txn.update(
          'pharmacists',
          {...values, 'updated_at': now},
          where: 'uid = ?',
          whereArgs: [uid],
        );
      }
      final pharmacyId = await _profileId(
        txn,
        'Pharmacists',
        'pharmacy_id',
        uid,
      );
      await txn.update(
        'Refill_Request',
        {'pharmacy_id': pharmacyId},
        where: 'pharmacy_uid=?',
        whereArgs: [uid],
      );
    });
  }

  Future<Map<String, Object?>?> getFamily(String uid) async {
    if (uid.trim().isEmpty) throw ArgumentError('Firebase UID is required.');
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'family_members',
        where: 'uid = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final patients = await txn.rawQuery(
        '''
        SELECT p.* FROM patients p
        JOIN patient_family_links l ON l.patient_id = p.patient_id
        WHERE l.family_id = ? ORDER BY p.patient_id
      ''',
        [rows.single['family_id']],
      );
      return {...rows.single, 'linked_patients': patients};
    });
  }

  Future<void> saveFamily(
    String uid,
    Map<String, dynamic> profile, {
    bool authoritative = false,
  }) async {
    if (uid.trim().isEmpty ||
        profile['uid'] != uid ||
        profile['role'] != 'family') {
      throw StateError('Only the authenticated family profile can be saved.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final values = <String, Object?>{};
      for (final entry in const {
        'name': 'name',
        'relationship': 'relationship',
        'phone': 'phone',
        'email': 'email',
      }.entries) {
        final value = profile[entry.key];
        if (value != null && value is! String) {
          throw ArgumentError('Invalid family profile field.');
        }
        if (authoritative) {
          values[entry.value] = value is String && value.trim().isNotEmpty
              ? value.trim()
              : null;
        } else if (value is String && value.trim().isNotEmpty) {
          values[entry.value] = value.trim();
        }
      }
      final caregiverUid = profile['caregiverId'];
      if (caregiverUid != null && caregiverUid is! String) {
        throw ArgumentError('Invalid caregiver UID.');
      }
      if (caregiverUid is String && caregiverUid.trim().isNotEmpty) {
        values['caregiver_uid'] = caregiverUid.trim();
      }
      if ((authoritative || profile.containsKey('caregiverId')) &&
          caregiverUid == null) {
        values['caregiver_uid'] = null;
        values['caregiver_id'] = null;
      }
      if (caregiverUid is String && caregiverUid.trim().isNotEmpty) {
        values['caregiver_id'] = await _profileId(
          txn,
          'Caregivers',
          'caregiver_id',
          caregiverUid.trim(),
        );
      }
      final existing = await txn.query(
        'family_members',
        where: 'uid = ?',
        whereArgs: [uid],
        limit: 1,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      int familyId;
      if (existing.isEmpty) {
        familyId = await txn.insert('family_members', {
          'uid': uid,
          ...values,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        familyId = existing.single['family_id'] as int;
        await txn.update(
          'family_members',
          {...values, 'updated_at': now},
          where: 'family_id = ?',
          whereArgs: [familyId],
        );
      }
      final linkedIds = profile['linkedPatientIds'] ?? const [];
      if (linkedIds is! List || linkedIds.any((id) => id is! String)) {
        throw ArgumentError('Invalid linked patient IDs.');
      }
      await txn.delete(
        'patient_family_links',
        where: 'family_id = ?',
        whereArgs: [familyId],
      );
      for (final patientUid in linkedIds.cast<String>().toSet()) {
        final patients = await txn.query(
          'patients',
          columns: ['patient_id'],
          where: 'uid = ?',
          whereArgs: [patientUid],
          limit: 1,
        );
        // Keep the Firestore UID relationship in the cloud when no local patient exists.
        if (patients.isNotEmpty) {
          await txn.insert('patient_family_links', {
            'family_id': familyId,
            'patient_id': patients.single['patient_id'],
          });
        }
      }
    });
  }

  Future<(DatabaseFactory, String)> _mobileDatabaseLocation() async {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      throw UnsupportedError(
        'Local SQLite records are available on Android and iOS.',
      );
    }
    return (
      databaseFactory,
      p.join(await getDatabasesPath(), ClinicalLocalSchema.databaseName),
    );
  }

  Future<LocalCaregiverRecord?> getCaregiver(String firebaseUid) async {
    if (firebaseUid.trim().isEmpty) {
      throw ArgumentError('Firebase UID is required.');
    }
    final db = await database;
    final rows = await db.query(
      'caregivers',
      where: 'uid = ?',
      whereArgs: [firebaseUid],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalCaregiverRecord.fromMap(rows.single);
  }

  /// Copies the authenticated caregiver's available Firebase profile fields.
  /// Transactions retain the local ID for future relationships. Missing/blank
  /// values are omitted so an incomplete profile cannot erase saved values.
  Future<LocalCaregiverRecord> saveCaregiver(
    UserModel profile, {
    required String authenticatedUid,
    bool authoritative = false,
  }) async {
    if (authenticatedUid.trim().isEmpty ||
        profile.uid != authenticatedUid ||
        profile.role != UserRole.caregiver) {
      throw StateError('Only the signed-in caregiver profile can be saved.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'caregivers',
        where: 'uid = ?',
        whereArgs: [authenticatedUid],
      );
      // Confirmed snapshots may clear optional fields; partial copies preserve them.
      final values = <String, Object?>{
        if (authoritative) 'phone': null,
        if (authoritative) 'profile_pic_url': null,
      };
      void include(String field, String? value) {
        if (value != null && value.trim().isNotEmpty) {
          values[field] = value.trim();
        }
      }

      include('name', profile.name);
      include('email', profile.email);
      include('phone', profile.phone);
      final image = profile.profilePicUrl;
      if (image != null && image.trim().isNotEmpty) {
        final uri = Uri.tryParse(image.trim());
        if (uri != null &&
            ['https', 'http'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty) {
          // Firebase download URLs may carry access tokens. Store only a reference.
          include(
            'profile_pic_url',
            uri.toString().split(RegExp(r'[?#]')).first,
          );
        }
      }
      if (rows.isEmpty &&
          (!values.containsKey('name') || !values.containsKey('email'))) {
        throw StateError(
          'A name and email are required to create a local record.',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      if (rows.isEmpty) {
        await txn.insert('caregivers', {
          ...values,
          'uid': authenticatedUid,
          'created_at': now,
          'updated_at': now,
        });
      } else if (values.entries.any(
        (entry) => rows.single[entry.key] != entry.value,
      )) {
        await txn.update(
          'caregivers',
          {...values, 'updated_at': now},
          where: 'uid = ?',
          whereArgs: [authenticatedUid],
        );
      }
      final saved = await txn.query(
        'caregivers',
        where: 'uid = ?',
        whereArgs: [authenticatedUid],
      );
      await _backfillCaregiver(
        txn,
        authenticatedUid,
        saved.single['caregiver_id'] as int,
      );
      return LocalCaregiverRecord.fromMap(saved.single);
    });
  }

  Future<LocalPatientRecord?> getPatient(String uid) async {
    if (uid.trim().isEmpty) {
      throw ArgumentError('Firebase UID is required.');
    }
    final db = await database;
    return db.transaction((txn) => _readPatient(txn, uid));
  }

  static Future<LocalPatientRecord?> _readPatient(
    DatabaseExecutor db,
    String uid,
  ) async {
    final rows = await db.query(
      'patients',
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final history = await db.query(
      'patient_medical_history',
      where: 'patient_id = ?',
      whereArgs: [rows.single['patient_id']],
      orderBy: 'history_id',
    );
    return LocalPatientRecord.fromMap(rows.single, history);
  }

  /// Copies only supported fields from the authenticated patient's Firestore
  /// document. Missing/null/blank fields preserve previous local values.
  Future<LocalPatientRecord> savePatient(
    String uid,
    Map<String, dynamic> profile, {
    required String authenticatedUid,
    bool authoritative = false,
  }) async {
    if (uid.trim().isEmpty ||
        uid != authenticatedUid ||
        profile['role'] != 'patient' ||
        (profile['uid'] != null && profile['uid'] != uid)) {
      throw StateError('Only the signed-in patient profile can be saved.');
    }
    return _savePatient(uid, profile, authoritative: authoritative);
  }

  /// Used after successful Firebase registration by a verified, signed-in
  /// caregiver. Ownership is checked separately from the patient's UID.
  Future<LocalPatientRecord> savePatientCreatedByCaregiver(
    String uid,
    Map<String, dynamic> profile, {
    required UserModel caregiver,
    bool authoritative = false,
  }) async {
    if (uid.trim().isEmpty ||
        caregiver.uid.trim().isEmpty ||
        caregiver.role != UserRole.caregiver ||
        profile['role'] != 'patient' ||
        profile['uid'] != uid ||
        profile['caregiverId'] != caregiver.uid) {
      throw StateError(
        'Only a verified caregiver can save their registered patient.',
      );
    }
    return _savePatient(uid, profile, authoritative: authoritative);
  }

  /// Cache a server-authorized patient shared with the signed-in family account.
  /// The caller checks that its Firebase session has not changed while fetching.
  Future<LocalPatientRecord> saveLinkedPatient(
    String uid,
    Map<String, dynamic> profile, {
    required UserModel family,
  }) async {
    if (uid.trim().isEmpty ||
        family.uid.trim().isEmpty ||
        family.role != UserRole.family ||
        !family.linkedPatientIds.contains(uid) ||
        family.caregiverId != profile['caregiverId'] ||
        profile['role'] != 'patient' ||
        profile['uid'] != uid) {
      throw StateError('Only a linked family account can cache this patient.');
    }
    return _savePatient(uid, profile, authoritative: true);
  }

  Future<LocalPatientRecord> _savePatient(
    String uid,
    Map<String, dynamic> profile, {
    bool authoritative = false,
  }) async {
    const fields = {
      'name': 'name',
      'icNumber': 'ic_number',
      'gender': 'gender',
      'dateOfBirth': 'date_of_birth',
      'phone': 'phone',
      'email': 'email',
      'address': 'address',
    };

    final values = <String, Object?>{};
    for (final field in fields.entries) {
      final value = profile[field.key];
      if (value != null && value is! String) {
        throw ArgumentError('Invalid patient profile field.');
      }
      if (authoritative) {
        values[field.value] = value is String && value.trim().isNotEmpty
            ? value.trim()
            : null;
      } else if (value is String && value.trim().isNotEmpty) {
        values[field.value] = value.trim();
      }
    }
    final historyValue =
        profile['medicalHistory'] ?? (authoritative ? const <String>[] : null);
    if (historyValue != null &&
        (historyValue is! List ||
            historyValue.any((item) => item is! String))) {
      throw ArgumentError('Invalid medical history.');
    }
    final conditions = historyValue is List
        ? historyValue
              .cast<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
        : null;
    final caregiverUid = profile['caregiverId'];
    if (caregiverUid != null && caregiverUid is! String) {
      throw ArgumentError('Invalid caregiver UID.');
    }
    final db = await database;
    return db.transaction((txn) async {
      if ((authoritative || profile.containsKey('caregiverId')) &&
          caregiverUid == null) {
        values['caregiver_uid'] = null;
        values['caregiver_id'] = null;
      }
      // Firestore caregiverId is a Firebase UID, never a local integer ID.
      // Do not copy another user's profile to manufacture a relationship.
      if (caregiverUid is String && caregiverUid.trim().isNotEmpty) {
        final caregivers = await txn.query(
          'caregivers',
          columns: ['caregiver_id'],
          where: 'uid = ?',
          whereArgs: [caregiverUid],
          limit: 1,
        );
        values['caregiver_uid'] = caregiverUid.trim();
        values['caregiver_id'] = caregivers.isEmpty
            ? null
            : caregivers.single['caregiver_id'];
      }
      final rows = await txn.query(
        'patients',
        where: 'uid = ?',
        whereArgs: [uid],
        limit: 1,
      );
      final int patientId;
      final now = DateTime.now().toUtc().toIso8601String();
      if (rows.isEmpty) {
        patientId = await txn.insert('patients', {
          ...values,
          'uid': uid,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        patientId = rows.single['patient_id'] as int;
        await txn.update(
          'patients',
          {...values, 'updated_at': now},
          where: 'patient_id = ?',
          whereArgs: [patientId],
        );
      }
      if (conditions != null) {
        final existing = await txn.query(
          'patient_medical_history',
          where: 'patient_id = ?',
          whereArgs: [patientId],
        );
        for (final entry in existing) {
          if (!conditions.contains(entry['medical_history'])) {
            await txn.delete(
              'patient_medical_history',
              where: 'history_id = ?',
              whereArgs: [entry['history_id']],
            );
          }
        }
        final oldConditions = existing
            .map((entry) => entry['medical_history'])
            .toSet();
        for (final condition in conditions.difference(oldConditions)) {
          await txn.insert('patient_medical_history', {
            'patient_id': patientId,
            'medical_history': condition,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }
      return (await _readPatient(txn, uid))!;
    });
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) await (await opening).close();
    _opening = null;
    _issuedIds.clear();
  }

  Future<int> allocateOfflineRecordId(String entity, String owner) async {
    final descriptor = LocalIdSchema.identityTables[entity];
    if (descriptor == null || owner.trim().isEmpty) {
      throw ArgumentError(
        'A record entity and signed-in account are required.',
      );
    }
    final db = await database;
    return db.transaction((txn) async {
      final (table, key) = descriptor;
      final issued = _issuedIds.putIfAbsent(entity, () => <int>{});
      while (true) {
        final id = IntegerRecordId.next();
        if (issued.contains(id)) continue;
        if ((await txn.query(
          table,
          columns: [key],
          where: '$key=?',
          whereArgs: [id],
          limit: 1,
        )).isNotEmpty) {
          continue;
        }
        issued.add(id);
        return id;
      }
    });
  }
}
