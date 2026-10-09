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

/// Owns the shared local database. Retains its existing name/API for caregivers.
class CaregiverSqliteService {
  CaregiverSqliteService({DatabaseFactory? factory, String? databasePath})
    : _factory = factory,
      _databasePath = databasePath;

  static final instance = CaregiverSqliteService();
  final DatabaseFactory? _factory;
  final String? _databasePath;
  Future<Database>? _opening;
  final StreamController<String> _medicationActionChanges =
      StreamController<String>.broadcast(sync: true);
  final StreamController<String> _refillRequestChanges =
      StreamController<String>.broadcast(sync: true);

  Stream<String> get medicationActionChanges =>
      _medicationActionChanges.stream;
  Stream<String> get refillRequestChanges => _refillRequestChanges.stream;

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    try {
      final (factory, databasePath) = _factory != null && _databasePath != null
          ? (_factory, _databasePath)
          : await _mobileDatabaseLocation();
      return await factory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 11,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE caregivers (
              caregiver_id INTEGER PRIMARY KEY AUTOINCREMENT,
              firebase_uid TEXT NOT NULL UNIQUE CHECK(length(trim(firebase_uid)) > 0),
              name TEXT NOT NULL CHECK(length(trim(name)) > 0),
              email TEXT NOT NULL CHECK(length(trim(email)) > 0),
              phone TEXT,
              profile_pic_url TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
            await _createPatientTables(db);
            await _createFamilyTables(db);
            await _createPharmacistTable(db);
            await _createPatientMedicationCache(db);
            await _createPatientAppointmentCache(db);
            await _createMedicationActionTable(db);
            await _createMoodTable(db);
            await _createRefillRequestTable(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              await _createPatientTables(db);
            }
            if (oldVersion < 3) await _createFamilyTables(db);
            if (oldVersion < 4) await _createPharmacistTable(db);
            if (oldVersion < 5) await _createPatientMedicationCache(db);
            if (oldVersion < 6) await _migrateMedicationCacheToPatientIds(db);
            if (oldVersion < 7) await _createPatientAppointmentCache(db);
            if (oldVersion < 8) {
              final columns = await db.rawQuery(
                'PRAGMA table_info(patient_appointment_cache)',
              );
              if (!columns.any((row) => row['name'] == 'remind_before')) {
                await db.execute(
                  'ALTER TABLE patient_appointment_cache ADD COLUMN remind_before INTEGER NOT NULL DEFAULT 0',
                );
              }
            }
            if (oldVersion < 9) await _createMedicationActionTable(db);
            if (oldVersion < 10) await _createMoodTable(db);
            if (oldVersion < 11) await _createRefillRequestTable(db);
          },
        ),
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<void> _createPatientTables(Database db) async {
    await db.execute('''
      CREATE TABLE patients (
        patient_id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT NOT NULL UNIQUE CHECK(length(trim(uid)) > 0),
        name TEXT,
        ic_number TEXT,
        gender TEXT,
        date_of_birth TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        caregiver_id INTEGER,
        FOREIGN KEY (caregiver_id) REFERENCES caregivers(caregiver_id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE patient_medical_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id INTEGER NOT NULL,
        medical_history TEXT,
        created_at TEXT,
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
        UNIQUE (patient_id, medical_history)
      )
    ''');
  }

  static Future<void> _createFamilyTables(Database db) async {
    await db.execute('''
      CREATE TABLE family_members (
        family_id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT NOT NULL UNIQUE,
        name TEXT,
        relationship TEXT,
        phone TEXT,
        email TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE patient_family_links (
        family_id INTEGER NOT NULL,
        patient_id INTEGER NOT NULL,
        PRIMARY KEY (family_id, patient_id),
        FOREIGN KEY (family_id) REFERENCES family_members(family_id) ON DELETE CASCADE,
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _createPharmacistTable(Database db) async {
    await db.execute('''
      CREATE TABLE pharmacists (
        pharmacy_id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT NOT NULL UNIQUE,
        name TEXT,
        phone TEXT,
        email TEXT
      )
    ''');
  }

  static Future<void> _createPatientMedicationCache(Database db) async {
    await db.execute('''
      CREATE TABLE patient_medication_cache (
        medication_id TEXT NOT NULL,
        patient_id INTEGER NOT NULL,
        caregiver_id TEXT NOT NULL,
        current_stock INTEGER NOT NULL,
        days_json TEXT NOT NULL,
        dosage TEXT NOT NULL,
        image_url TEXT,
        interval_days INTEGER NOT NULL,
        name TEXT NOT NULL,
        patient_name TEXT NOT NULL,
        remind_refill INTEGER NOT NULL,
        remind_threshold INTEGER NOT NULL,
        start_date TEXT,
        time TEXT NOT NULL,
        timezone TEXT NOT NULL,
        type TEXT NOT NULL,
        PRIMARY KEY (patient_id, medication_id),
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX patient_medication_cache_patient_id
      ON patient_medication_cache(patient_id)
    ''');
  }

  static Future<void> _createPatientAppointmentCache(Database db) async {
    await db.execute('''
      CREATE TABLE patient_appointment_cache (
        appointment_id TEXT NOT NULL,
        patient_id INTEGER NOT NULL,
        caregiver_id TEXT NOT NULL,
        date TEXT NOT NULL,
        location TEXT NOT NULL,
        patient_name TEXT NOT NULL,
        remind_before INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        time TEXT NOT NULL,
        title TEXT NOT NULL,
        PRIMARY KEY (patient_id, appointment_id),
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX patient_appointment_cache_patient_id
      ON patient_appointment_cache(patient_id)
    ''');
  }

  static Future<void> _createMedicationActionTable(Database db) async {
    await db.execute('''
      CREATE TABLE MedicationAction (
        id TEXT PRIMARY KEY NOT NULL,
        action TEXT NOT NULL,
        medicationId TEXT NOT NULL,
        medicationName TEXT NOT NULL,
        patientId TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        snoozeUntil INTEGER,
        syncStatus TEXT NOT NULL CHECK(syncStatus IN ('pending', 'synced'))
      )
    ''');
    await db.execute('''
      CREATE INDEX medication_action_patient_timestamp
      ON MedicationAction(patientId, timestamp DESC)
    ''');
    await db.execute('''
      CREATE INDEX medication_action_sync_status
      ON MedicationAction(patientId, syncStatus)
    ''');
  }

  static Future<void> _createMoodTable(Database db) async {
    await db.execute('''
      CREATE TABLE Mood (
        id TEXT PRIMARY KEY NOT NULL,
        date TEXT NOT NULL,
        emoji TEXT NOT NULL,
        moodIndex INTEGER NOT NULL,
        moodLabel TEXT NOT NULL,
        patientId TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX mood_patient_date_timestamp
      ON Mood(patientId, date, timestamp DESC)
    ''');
  }

  static Future<void> _createRefillRequestTable(Database db) async {
    await db.execute('''
      CREATE TABLE RefillRequest (
        id TEXT PRIMARY KEY NOT NULL,
        caregiverId TEXT NOT NULL,
        caregiverName TEXT NOT NULL,
        medicationId TEXT NOT NULL,
        medicationName TEXT NOT NULL,
        patientId TEXT NOT NULL,
        patientName TEXT NOT NULL,
        quantityLeft INTEGER NOT NULL,
        quantityRequested INTEGER NOT NULL,
        requestAt INTEGER NOT NULL,
        status TEXT NOT NULL,
        updateAt INTEGER
      )
    ''');
    await db.execute('''
      CREATE INDEX refill_request_caregiver_date
      ON RefillRequest(caregiverId, requestAt DESC)
    ''');
  }

  /// Stores Firestore-confirmed requests; IDs make listener replays idempotent.
  Future<void> saveRefillRequest(RefillRequest request) async {
    if (request.id.trim().isEmpty ||
        request.caregiverId.trim().isEmpty ||
        request.patientId.trim().isEmpty) {
      throw ArgumentError('Invalid refill request.');
    }
    await (await database).insert(
      'RefillRequest',
      _refillRequestRow(request),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _refillRequestChanges.add(request.caregiverId);
  }

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
      for (final request in requests) {
        await txn.insert(
          'RefillRequest',
          _refillRequestRow(request),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _refillRequestChanges.add(caregiverId);
  }

  Future<List<RefillRequest>> getRefillRequests(String caregiverId) async {
    if (caregiverId.trim().isEmpty) return [];
    final rows = await (await database).query(
      'RefillRequest',
      where: 'caregiverId = ?',
      whereArgs: [caregiverId],
      orderBy: 'requestAt DESC, id DESC',
    );
    return rows
        .map((row) => RefillRequest.fromMap(row['id'] as String, row))
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

  static Map<String, Object?> _refillRequestRow(RefillRequest request) => {
    'id': request.id,
    'caregiverId': request.caregiverId,
    'caregiverName': request.caregiverName,
    'medicationId': request.medicationId,
    'medicationName': request.medicationName,
    'patientId': request.patientId,
    'patientName': request.patientName,
    'quantityLeft': request.quantityLeft,
    'quantityRequested': request.quantityRequested,
    'requestAt': request.requestedAt,
    'status': request.status,
    'updateAt': request.updatedAt,
  };

  /// Insert a server-confirmed mood. The Firestore document ID is the stable
  /// primary key, so duplicate local retries cannot create extra records.
  Future<void> saveMood(DailyMood mood) async {
    if (mood.id.trim().isEmpty || mood.patientId.trim().isEmpty) {
      throw ArgumentError('Invalid mood record.');
    }
    await (await database).insert(
      'Mood',
      mood.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteMood(String id) async {
    if (id.trim().isEmpty) return;
    await (await database).delete('Mood', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _migrateMedicationCacheToPatientIds(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'patient_medication_cache'",
    );
    if (tables.isEmpty) {
      await _createPatientMedicationCache(db);
      return;
    }
    await db.execute(
      'ALTER TABLE patient_medication_cache RENAME TO patient_medication_cache_v5',
    );
    await db.execute('''
      CREATE TABLE patient_medication_cache (
        medication_id TEXT NOT NULL,
        patient_id INTEGER NOT NULL,
        caregiver_id TEXT NOT NULL,
        current_stock INTEGER NOT NULL,
        days_json TEXT NOT NULL,
        dosage TEXT NOT NULL,
        image_url TEXT,
        interval_days INTEGER NOT NULL,
        name TEXT NOT NULL,
        patient_name TEXT NOT NULL,
        remind_refill INTEGER NOT NULL,
        remind_threshold INTEGER NOT NULL,
        start_date TEXT,
        time TEXT NOT NULL,
        timezone TEXT NOT NULL,
        type TEXT NOT NULL,
        PRIMARY KEY (patient_id, medication_id),
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO patient_medication_cache (
        medication_id, patient_id, caregiver_id, current_stock, days_json,
        dosage, image_url, interval_days, name, patient_name, remind_refill,
        remind_threshold, start_date, time, timezone, type
      )
      SELECT c.medication_id, p.patient_id, c.caregiver_id, c.current_stock,
        c.days_json, c.dosage, c.image_url, c.interval_days, c.name,
        c.patient_name, c.remind_refill, c.remind_threshold, c.start_date,
        c.time, c.timezone, c.type
      FROM patient_medication_cache_v5 c
      JOIN patients p ON p.uid = c.patient_uid
    ''');
    await db.execute('DROP TABLE patient_medication_cache_v5');
    await db.execute('''
      CREATE INDEX patient_medication_cache_patient_id
      ON patient_medication_cache(patient_id)
    ''');
  }

  Future<List<Medication>> getCachedPatientMedications(
    String patientUid,
  ) async {
    if (patientUid.trim().isEmpty) {
      throw ArgumentError('Firebase UID is required.');
    }
    final db = await database;
    final patients = await db.query(
      'patients',
      columns: ['patient_id'],
      where: 'uid = ?',
      whereArgs: [patientUid],
      limit: 1,
    );
    if (patients.isEmpty) return [];
    final patientId = patients.single['patient_id'];
    final rows = await db.query(
      'patient_medication_cache',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'time, medication_id',
    );
    return rows.map((row) {
      final days = jsonDecode(row['days_json'] as String);
      return Medication.fromMap(row['medication_id'] as String, {
        'caregiverId': row['caregiver_id'],
        'currentStock': row['current_stock'],
        'days': days,
        'dosage': row['dosage'],
        'imageUrl': row['image_url'],
        'intervalDays': row['interval_days'],
        'name': row['name'],
        'patientId': patientUid,
        'patientName': row['patient_name'],
        'remindRefill': (row['remind_refill'] as int) != 0,
        'remindThreshold': row['remind_threshold'],
        'startDate': row['start_date'],
        'time': row['time'],
        'timeZone': row['timezone'],
        'type': row['type'],
      });
    }).toList();
  }

  /// Replaces one patient's cache only after Firestore produced a confirmed
  /// snapshot. The caller must never call this with a failed or cached fetch.
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
      final patients = await txn.query(
        'patients',
        columns: ['patient_id'],
        where: 'uid = ?',
        whereArgs: [patientUid],
        limit: 1,
      );
      // Do not fabricate a Patient when no local row exists.
      if (patients.isEmpty) return;
      final patientId = patients.single['patient_id'];
      await txn.delete(
        'patient_medication_cache',
        where: 'patient_id = ?',
        whereArgs: [patientId],
      );
      for (final medication in medications) {
        await txn.insert('patient_medication_cache', {
          'medication_id': medication.id,
          'patient_id': patientId,
          'caregiver_id': medication.caregiverId,
          'current_stock': medication.currentStock,
          'days_json': jsonEncode(medication.days),
          'dosage': medication.dosage,
          'image_url': medication.imageUrl,
          'interval_days': medication.intervalDays,
          'name': medication.name,
          'patient_name': medication.patientName,
          'remind_refill': medication.remindRefill ? 1 : 0,
          'remind_threshold': medication.remindThreshold,
          'start_date': medication.startDate,
          'time': medication.time,
          'timezone': medication.timeZone,
          'type': medication.type,
        });
      }
    });
  }

  Future<List<Appointment>> getCachedPatientAppointments(
    String patientUid,
  ) async {
    if (patientUid.trim().isEmpty) {
      throw ArgumentError('Firebase UID is required.');
    }
    final db = await database;
    final patients = await db.query(
      'patients',
      columns: ['patient_id'],
      where: 'uid = ?',
      whereArgs: [patientUid],
      limit: 1,
    );
    if (patients.isEmpty) return [];
    final rows = await db.query(
      'patient_appointment_cache',
      where: 'patient_id = ?',
      whereArgs: [patients.single['patient_id']],
      orderBy: 'date, time, appointment_id',
    );
    return rows
        .map(
          (row) => Appointment.fromMap(
            row['appointment_id'] as String,
            {
              'caregiverId': row['caregiver_id'],
              'date': row['date'],
              'location': row['location'],
              'patientId': patientUid,
              'patientName': row['patient_name'],
              'remindBefore': row['remind_before'],
              'status': row['status'],
              'time': row['time'],
              'title': row['title'],
            },
          ),
        )
        .toList();
  }

  /// Removes legacy local appointment rows. Appointment schedules are read
  /// from Firestore and displayed directly; they are not part of the local
  /// patient/medication database.
  Future<void> clearCachedPatientAppointments(String patientUid) async {
    if (patientUid.trim().isEmpty) return;
    final db = await database;
    final patients = await db.query(
      'patients',
      columns: ['patient_id'],
      where: 'uid = ?',
      whereArgs: [patientUid],
      limit: 1,
    );
    if (patients.isEmpty) return;
    await db.delete(
      'patient_appointment_cache',
      where: 'patient_id = ?',
      whereArgs: [patients.single['patient_id']],
    );
  }

  /// Replaces a patient's cache only after a server-confirmed Firestore snapshot.
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
      final patients = await txn.query(
        'patients',
        columns: ['patient_id'],
        where: 'uid = ?',
        whereArgs: [patientUid],
        limit: 1,
      );
      // Keep Firestore relationships without inventing a local Patient row.
      if (patients.isEmpty) return;
      final patientId = patients.single['patient_id'];
      await txn.delete(
        'patient_appointment_cache',
        where: 'patient_id = ?',
        whereArgs: [patientId],
      );
      for (final appointment in appointments) {
        await txn.insert('patient_appointment_cache', {
          'appointment_id': appointment.id,
          'patient_id': patientId,
          'caregiver_id': appointment.caregiverId,
          'date': appointment.date,
          'location': appointment.location,
          'patient_name': appointment.patientName,
          'remind_before': appointment.remindBefore,
          'status': appointment.status,
          'time': appointment.time,
          'title': appointment.title,
        });
      }
    });
  }

  Future<void> saveMedicationAction(
    MedicationAction action, {
    String? syncStatus,
  }) async {
    final status = syncStatus ?? action.syncStatus;
    if (action.id.trim().isEmpty ||
        action.patientId.trim().isEmpty ||
        !['taken', 'skipped', 'snoozed'].contains(action.action) ||
        !['pending', 'synced'].contains(status)) {
      throw ArgumentError('Invalid medication action record.');
    }
    final values = <String, Object?>{
      'id': action.id,
      'action': action.action,
      'medicationId': action.medicationId,
      'medicationName': action.medicationName,
      'patientId': action.patientId,
      'timestamp': action.timestamp,
      'snoozeUntil': action.snoozedUntil,
      'syncStatus': status,
    };
    final db = await database;
    if (status == 'pending') {
      // Retrying the same action ID never creates a second history row.
      await db.insert(
        'MedicationAction',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await db.insert(
        'MedicationAction',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    _medicationActionChanges.add(action.patientId);
  }

  Future<void> setMedicationActionSyncStatus(String id, String status) async {
    if (id.trim().isEmpty || !['pending', 'synced'].contains(status)) {
      throw ArgumentError('Invalid medication action sync state.');
    }
    final db = await database;
    final rows = await db.query(
      'MedicationAction',
      where: 'id = ?',
      whereArgs: [id],
      columns: ['patientId'],
      limit: 1,
    );
    await db.update(
      'MedicationAction',
      {'syncStatus': status},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isNotEmpty) {
      _medicationActionChanges.add(rows.single['patientId'] as String);
    }
  }

  Future<List<MedicationAction>> getMedicationActions(String patientUid) async {
    if (patientUid.trim().isEmpty) return [];
    final rows = await (await database).query(
      'MedicationAction',
      where: 'patientId = ?',
      whereArgs: [patientUid],
      orderBy: 'timestamp DESC, id DESC',
    );
    return rows
        .map(
          (row) => MedicationAction.fromMap(
            row['id'] as String,
            {
              'action': row['action'],
              'medicationId': row['medicationId'],
              'medicationName': row['medicationName'],
              'patientId': row['patientId'],
              'timestamp': row['timestamp'],
              'snoozeUntil': row['snoozeUntil'],
              'syncStatus': row['syncStatus'],
            },
          ),
        )
        .toList();
  }

  Future<List<MedicationAction>> getPendingMedicationActions(
    String patientUid,
  ) async {
    if (patientUid.trim().isEmpty) return [];
    final rows = await (await database).query(
      'MedicationAction',
      where: 'patientId = ? AND syncStatus = ?',
      whereArgs: [patientUid, 'pending'],
      orderBy: 'timestamp ASC, id ASC',
    );
    return rows
        .map(
          (row) => MedicationAction.fromMap(
            row['id'] as String,
            {
              'action': row['action'],
              'medicationId': row['medicationId'],
              'medicationName': row['medicationName'],
              'patientId': row['patientId'],
              'timestamp': row['timestamp'],
              'snoozeUntil': row['snoozeUntil'],
              'syncStatus': row['syncStatus'],
            },
          ),
        )
        .toList();
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

  Future<void> savePharmacist(String uid, Map<String, dynamic> profile) async {
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
      if (value is String && value.trim().isNotEmpty) {
        values[field] = value.trim();
      }
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'pharmacists',
        where: 'uid = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert('pharmacists', {'uid': uid, ...values});
      } else if (values.isNotEmpty) {
        await txn.update(
          'pharmacists',
          values,
          where: 'uid = ?',
          whereArgs: [uid],
        );
      }
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

  Future<void> saveFamily(String uid, Map<String, dynamic> profile) async {
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
        final value =
            profile[entry.key] ??
            (entry.key == 'relationship' ? profile['address'] : null);
        if (value != null && value is! String) {
          throw ArgumentError('Invalid family profile field.');
        }
        if (value is String && value.trim().isNotEmpty) {
          values[entry.value] = value.trim();
        }
      }
      final existing = await txn.query(
        'family_members',
        where: 'uid = ?',
        whereArgs: [uid],
        limit: 1,
      );
      int familyId;
      if (existing.isEmpty) {
        familyId = await txn.insert('family_members', {'uid': uid, ...values});
      } else {
        familyId = existing.single['family_id'] as int;
        if (values.isNotEmpty) {
          await txn.update(
            'family_members',
            values,
            where: 'family_id = ?',
            whereArgs: [familyId],
          );
        }
      }
      final linkedIds =
          profile['linkedPatientIds'] ??
          (profile['linkedPatientId'] == null
              ? const []
              : [profile['linkedPatientId']]);
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
      p.join(await getDatabasesPath(), 'medicare_local.db'),
    );
  }

  Future<LocalCaregiverRecord?> getCaregiver(String firebaseUid) async {
    if (firebaseUid.trim().isEmpty) {
      throw ArgumentError('Firebase UID is required.');
    }
    final db = await database;
    final rows = await db.query(
      'caregivers',
      where: 'firebase_uid = ?',
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
        where: 'firebase_uid = ?',
        whereArgs: [authenticatedUid],
      );
      final values = <String, Object?>{};
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
          'firebase_uid': authenticatedUid,
          'created_at': now,
          'updated_at': now,
        });
      } else if (values.entries.any(
        (entry) => rows.single[entry.key] != entry.value,
      )) {
        await txn.update(
          'caregivers',
          {...values, 'updated_at': now},
          where: 'firebase_uid = ?',
          whereArgs: [authenticatedUid],
        );
      }
      final saved = await txn.query(
        'caregivers',
        where: 'firebase_uid = ?',
        whereArgs: [authenticatedUid],
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
  }) async {
    if (uid.trim().isEmpty ||
        uid != authenticatedUid ||
        profile['role'] != 'patient' ||
        (profile['uid'] != null && profile['uid'] != uid)) {
      throw StateError('Only the signed-in patient profile can be saved.');
    }
    return _savePatient(uid, profile);
  }

  /// Used after successful Firebase registration by a verified, signed-in
  /// caregiver. Ownership is checked separately from the patient's UID.
  Future<LocalPatientRecord> savePatientCreatedByCaregiver(
    String uid,
    Map<String, dynamic> profile, {
    required UserModel caregiver,
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
    return _savePatient(uid, profile);
  }

  Future<LocalPatientRecord> _savePatient(
    String uid,
    Map<String, dynamic> profile,
  ) async {
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
      if (value is String && value.trim().isNotEmpty) {
        values[field.value] = value.trim();
      }
    }
    final historyValue = profile['medicalHistory'];
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
      // Firestore caregiverId is a Firebase UID, never a local integer ID.
      // Do not copy another user's profile to manufacture a relationship.
      if (caregiverUid is String && caregiverUid.trim().isNotEmpty) {
        final caregivers = await txn.query(
          'caregivers',
          columns: ['caregiver_id'],
          where: 'firebase_uid = ?',
          whereArgs: [caregiverUid],
          limit: 1,
        );
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
      if (rows.isEmpty) {
        patientId = await txn.insert('patients', {...values, 'uid': uid});
      } else {
        patientId = rows.single['patient_id'] as int;
        if (values.isNotEmpty) {
          await txn.update(
            'patients',
            values,
            where: 'patient_id = ?',
            whereArgs: [patientId],
          );
        }
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
  }
}
