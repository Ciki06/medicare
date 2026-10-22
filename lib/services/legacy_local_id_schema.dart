import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

/// Historical pre-v14 upgrade only. Helper tables exist within the upgrade
/// transaction and are removed before committing the current schema.
class LegacyLocalIdSchema {
  static Future<void> createSharedIdTables(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE cloud_id_maps (id INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, uid TEXT NOT NULL, record_id INTEGER NOT NULL, UNIQUE(entity, uid))',
    );
    await db.execute(
      'CREATE TABLE reserved_record_ids (id INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, owner_uid TEXT NOT NULL, start_id INTEGER NOT NULL, end_id INTEGER NOT NULL, next_id INTEGER NOT NULL, UNIQUE(entity, owner_uid, start_id))',
    );
  }

  static const references = {
    'patient_id': ('patients', 'patient_id'),
    'patientId': ('patients', 'patient_id'),
    'caregiver_id': ('caregivers', 'caregiver_id'),
    'caregiverId': ('caregivers', 'caregiver_id'),
    'medication_id': ('medication_keys', 'medication_id'),
    'medicationId': ('medication_keys', 'medication_id'),
    'appointment_id': ('appointment_keys', 'appointment_id'),
  };

  static String uidColumn(String field) => switch (field) {
    'patientId' || 'patient_id' => 'patient_uid',
    'caregiverId' || 'caregiver_id' => 'caregiver_uid',
    'medicationId' || 'medication_id' => 'medication_uid',
    _ => 'appointment_uid',
  };

  static Future<int?> resolve(
    DatabaseExecutor db,
    String field,
    String uid, {
    bool create = false,
  }) async {
    final (table, key) = references[field]!;
    var rows = await db.query(
      table,
      columns: [key],
      where: 'uid = ?',
      whereArgs: [uid],
    );
    if (rows.isEmpty && create && table != 'caregivers') {
      final now = DateTime.now().toUtc().toIso8601String();
      final entity = table == 'medication_keys'
          ? 'medications'
          : (table == 'appointment_keys' ? 'appointments' : table);
      final mapping = await db.query(
        'cloud_id_maps',
        columns: ['record_id'],
        where: 'entity = ? AND uid = ?',
        whereArgs: [entity, uid],
      );
      final canonical =
          (mapping.isEmpty ? null : mapping.single['record_id'] as int?) ??
          (table.endsWith('_keys') ? int.tryParse(uid) : null);
      await db.insert(table, {
        key: ?canonical,
        'uid': uid,
        if (table == 'patients') 'created_at': now,
        if (table == 'patients') 'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      rows = await db.query(
        table,
        columns: [key],
        where: 'uid = ?',
        whereArgs: [uid],
      );
    }
    return rows.isEmpty ? null : rows.single[key] as int;
  }

  static Future<Map<String, Object?>> encode(
    DatabaseExecutor db,
    Map<String, Object?> source,
  ) async {
    final row = Map<String, Object?>.from(source);
    if (row.containsKey('id')) row['uid'] = row.remove('id');
    for (final field in references.keys) {
      final value = row[field];
      if (value is int) {
        final (table, key) = references[field]!;
        final rows = await db.query(
          table,
          columns: ['uid'],
          where: '$key = ?',
          whereArgs: [value],
        );
        row[uidColumn(field)] = rows.single['uid'];
        continue;
      }
      if (value is! String) continue;
      row[uidColumn(field)] = value;
      row[field] = await resolve(db, field, value, create: true);
    }
    return row;
  }

  static Future<void> migrate(Database db) async {
    // Save the original schema and every row before changing an installed DB.
    // A fresh, empty database needs no backup. The upgrade transaction still
    // rolls back automatically if any row cannot be converted.
    final originalTables = await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    final original = <String, Object?>{};
    var rowCount = 0;
    for (final table in originalTables) {
      final name = table['name'] as String;
      final rows = await db.query(name);
      rowCount += rows.length;
      original[name] = {'sql': table['sql'], 'rows': rows};
    }
    if (rowCount > 0 && db.path != inMemoryDatabasePath) {
      await File(
        '${db.path}.before-integer-ids.json',
      ).writeAsString(jsonEncode(original), flush: true);
    }
    await db.execute(
      'ALTER TABLE caregivers RENAME COLUMN firebase_uid TO uid',
    );
    for (final entry in const {
      'medication_keys': 'medication_id',
      'appointment_keys': 'appointment_id',
    }.entries) {
      await db.execute(
        'CREATE TABLE ${entry.key} (${entry.value} INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT NOT NULL UNIQUE)',
      );
    }
    // Read every row before rebuilding, including history whose schedules have
    // already been deleted. Never discard an unmatched cloud relationship.
    const tables = [
      'family_members',
      'pharmacists',
      'patient_medication_cache',
      'patient_appointment_cache',
      'MedicationAction',
      'Mood',
      'RefillRequest',
    ];
    final snapshots = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      snapshots[table] = await db.query(table, orderBy: 'rowid');
    }
    // Family rows are referenced by patient_family_links, so change their
    // caregiver column in place and preserve their existing integer keys.
    for (final table in const ['family_members', 'pharmacists']) {
      await db.execute(
        'ALTER TABLE $table RENAME COLUMN caregiver_id TO caregiver_uid',
      );
      await db.execute(
        'ALTER TABLE $table ADD COLUMN caregiver_id INTEGER REFERENCES caregivers(caregiver_id) ON DELETE SET NULL',
      );
      await db.execute(
        'UPDATE $table SET caregiver_id = (SELECT caregiver_id FROM caregivers WHERE uid = $table.caregiver_uid)',
      );
    }
    for (final table in tables.skip(2)) {
      final info = await db.rawQuery('PRAGMA table_info("$table")');
      await db.execute('DROP TABLE "$table"');
      final definitions = <String>[];
      for (final column in info) {
        final name = column['name'] as String;
        if (name == 'id') {
          definitions.add('id INTEGER PRIMARY KEY AUTOINCREMENT');
          definitions.add('uid TEXT NOT NULL UNIQUE');
        } else if (references.containsKey(name)) {
          final (target, key) = references[name]!;
          final onDelete = name.startsWith('caregiver')
              ? ' ON DELETE SET NULL'
              : (target == 'patients' ? ' ON DELETE CASCADE' : '');
          definitions.add(
            '$name INTEGER ${name.startsWith('caregiver') ? '' : 'NOT NULL'} REFERENCES $target($key)$onDelete',
          );
          definitions.add(
            '${uidColumn(name)} TEXT ${name.startsWith('caregiver') ? '' : 'NOT NULL'}',
          );
        } else {
          final fk = name == 'pharmacy_id'
              ? ' REFERENCES pharmacists(pharmacy_id) ON DELETE SET NULL'
              : '';
          final defaultValue = column['dflt_value'] == null
              ? ''
              : ' DEFAULT ${column['dflt_value']}';
          definitions.add(
            '$name ${column['type']} ${column['notnull'] == 1 ? 'NOT NULL' : ''}$defaultValue$fk',
          );
        }
      }
      if (table == 'patient_medication_cache') {
        definitions.add('PRIMARY KEY (patient_id, medication_id)');
      }
      if (table == 'patient_appointment_cache') {
        definitions.add('PRIMARY KEY (patient_id, appointment_id)');
      }
      if (table == 'MedicationAction') {
        definitions.add("CHECK(syncStatus IN ('pending', 'synced'))");
      }
      await db.execute('CREATE TABLE "$table" (${definitions.join(', ')})');
      for (final source in snapshots[table]!) {
        final row = await encode(db, source);
        await db.insert(table, row);
      }
    }
    for (final sql in const [
      'CREATE INDEX medication_action_patient_timestamp ON MedicationAction(patientId, timestamp DESC)',
      'CREATE INDEX medication_action_sync_status ON MedicationAction(patientId, syncStatus)',
      'CREATE INDEX mood_patient_date_timestamp ON Mood(patientId, date, timestamp DESC)',
      'CREATE INDEX refill_request_caregiver_date ON RefillRequest(caregiverId, requestAt DESC)',
      'CREATE INDEX patient_medication_cache_patient_id ON patient_medication_cache(patient_id)',
      'CREATE INDEX patient_appointment_cache_patient_id ON patient_appointment_cache(patient_id)',
    ]) {
      await db.execute(sql);
    }
    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) {
      throw StateError('Local ID migration has invalid relationships.');
    }
  }
}
