import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

/// Mirrors cloud integer IDs in SQLite while retaining authentication UIDs
/// and legacy aliases separately for synchronization and migration.
class LocalIdSchema {
  static Future<void> createSharedIdTables(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE cloud_id_maps (id INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, uid TEXT NOT NULL, record_id INTEGER NOT NULL, UNIQUE(entity, uid))',
    );
    await db.execute(
      'CREATE TABLE reserved_record_ids (id INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, owner_uid TEXT NOT NULL, start_id INTEGER NOT NULL, end_id INTEGER NOT NULL, next_id INTEGER NOT NULL, UNIQUE(entity, owner_uid, start_id))',
    );
  }

  static const identityTables = {
    'caregivers': ('caregivers', 'caregiver_id'),
    'patients': ('patients', 'patient_id'),
    'family_members': ('family_members', 'family_id'),
    'pharmacists': ('pharmacists', 'pharmacy_id'),
    'medications': ('medication_keys', 'medication_id'),
    'appointments': ('appointment_keys', 'appointment_id'),
    'medication_actions': ('MedicationAction', 'id'),
    'moods': ('Mood', 'id'),
    'refill_requests': ('RefillRequest', 'id'),
  };

  /// Re-key every local table and its foreign keys in one transaction. First
  /// move keys to unused temporary integers so swaps (1→2, 2→1) cannot collide.
  static Future<void> align(
    DatabaseExecutor db,
    Map<String, Map<String, int>> maps,
  ) async {
    await db.execute('PRAGMA defer_foreign_keys = ON');
    final tableNames = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final references = <String, List<(String, String)>>{};
    for (final item in tableNames) {
      final table = item['name'] as String;
      for (final fk in await db.rawQuery('PRAGMA foreign_key_list("$table")')) {
        references.putIfAbsent(fk['table'] as String, () => []).add((
          table,
          fk['from'] as String,
        ));
      }
    }
    for (final entity in maps.entries) {
      final descriptor = identityTables[entity.key];
      if (descriptor == null) continue;
      if (entity.value.values.any((id) => id <= 0) ||
          entity.value.values.toSet().length != entity.value.length) {
        throw StateError('Invalid or duplicate shared IDs.');
      }
      final (table, key) = descriptor;
      final rows = await db.query(table);
      final changes = <(int, int, int, String)>[];
      var temporary =
          rows.fold<int>(
            -1000000000000,
            (smallest, row) =>
                (row[key] as int) < smallest ? row[key] as int : smallest,
          ) -
          1;
      for (final row in rows) {
        final uid = row['uid'] as String;
        final id = entity.value[uid];
        if (id == null) continue;
        changes.add((row[key] as int, temporary--, id, uid));
      }
      Future<void> move(int oldId, int newId) async {
        await db.update(
          table,
          {key: newId},
          where: '$key = ?',
          whereArgs: [oldId],
        );
        for (final (child, field)
            in references[table] ?? <(String, String)>[]) {
          await db.update(
            child,
            {field: newId},
            where: '$field = ?',
            whereArgs: [oldId],
          );
        }
      }

      // Preserve unmapped offline records if a cloud key needs their former
      // local number. They receive a shared integer ID when synchronization runs.
      final moving = changes.map((change) => change.$1).toSet();
      final destinations = changes.map((change) => change.$3).toSet();
      for (final row in rows) {
        final old = row[key] as int;
        if (!moving.contains(old) && destinations.contains(old)) {
          await move(old, temporary--);
        }
      }
      for (final change in changes) {
        await move(change.$1, change.$2);
      }
      for (final change in changes) {
        await move(change.$2, change.$3);
        if (!const [
          'caregivers',
          'patients',
          'family_members',
          'pharmacists',
        ].contains(entity.key)) {
          final canonicalUid = change.$3.toString();
          await db.update(
            table,
            {'uid': canonicalUid},
            where: '$key = ?',
            whereArgs: [change.$3],
          );
          for (final (child, field)
              in references[table] ?? <(String, String)>[]) {
            await db.update(
              child,
              {uidColumn(field): canonicalUid},
              where: '$field = ?',
              whereArgs: [change.$3],
            );
          }
        }
      }
      for (final entry in entity.value.entries) {
        final existing = await db.query(
          'cloud_id_maps',
          columns: ['id'],
          where: 'entity = ? AND uid = ?',
          whereArgs: [entity.key, entry.key],
        );
        if (existing.isEmpty) {
          await db.insert('cloud_id_maps', {
            'entity': entity.key,
            'uid': entry.key,
            'record_id': entry.value,
          });
        } else {
          await db.update(
            'cloud_id_maps',
            {'record_id': entry.value},
            where: 'id = ?',
            whereArgs: [existing.single['id']],
          );
        }
      }
    }
    if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw StateError('Shared IDs have invalid local relationships.');
    }
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
        if (canonical != null) key: canonical,
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

  static Future<void> store(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> source, {
    bool ignoreExisting = false,
  }) async {
    final row = await encode(db, source);
    final canonical = int.tryParse(row['uid'] as String);
    if (canonical != null && canonical > 0) row['id'] = canonical;
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'uid = ?',
      whereArgs: [row['uid']],
    );
    if (rows.isEmpty) {
      await db.insert(table, row);
    } else if (!ignoreExisting) {
      await db.update(
        table,
        row,
        where: 'id = ?',
        whereArgs: [rows.single['id']],
      );
    }
  }

  static Map<String, Object?> decode(Map<String, Object?> source) {
    final row = Map<String, Object?>.from(source);
    if (row.containsKey('uid') && row.containsKey('id')) row['id'] = row['uid'];
    for (final field in references.keys) {
      if (row.containsKey(uidColumn(field))) row[field] = row[uidColumn(field)];
    }
    return row;
  }

  static Future<void> backfillCaregiver(
    DatabaseExecutor db,
    String uid,
    int id,
  ) async {
    for (final table in const [
      'family_members',
      'pharmacists',
      'patient_medication_cache',
      'patient_appointment_cache',
      'RefillRequest',
    ]) {
      final field = table == 'RefillRequest' ? 'caregiverId' : 'caregiver_id';
      await db.update(
        table,
        {field: id},
        where: 'caregiver_uid = ?',
        whereArgs: [uid],
      );
    }
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
