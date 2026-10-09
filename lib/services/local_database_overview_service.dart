import 'package:firebase_auth/firebase_auth.dart';

import 'caregiver_sqlite_service.dart';

class LocalDatabaseColumn {
  const LocalDatabaseColumn({
    required this.name,
    required this.type,
    required this.primaryKey,
    required this.requiredValue,
    this.references,
  });
  final String name;
  final String type;
  final bool primaryKey;
  final bool requiredValue;
  final String? references;
}

class LocalDatabaseTable {
  LocalDatabaseTable({
    required this.name,
    required List<LocalDatabaseColumn> columns,
    required List<Map<String, Object?>> rows,
  }) : columns = List.unmodifiable(columns),
       rows = List.unmodifiable(rows.map(Map<String, Object?>.unmodifiable));

  final String name;
  final List<LocalDatabaseColumn> columns;
  final List<Map<String, Object?>> rows;
  String get title => switch (name) {
    'caregivers' => 'Caregivers',
    'patients' => 'Patients',
    'patient_medical_history' => 'Medical history',
    'patient_medication_cache' => 'Patient medication schedules',
    'patient_appointment_cache' => 'Patient appointment schedules',
    'MedicationAction' => 'Medication actions',
    'Mood' => 'Mood history',
    'RefillRequest' => 'Refill requests',
    _ => localDatabaseFieldLabel(name),
  };
}

class LocalDatabaseOverview {
  LocalDatabaseOverview({
    required this.version,
    required List<LocalDatabaseTable> tables,
  }) : tables = List.unmodifiable(tables);
  final int version;
  final List<LocalDatabaseTable> tables;
  int get recordCount =>
      tables.fold(0, (count, table) => count + table.rows.length);
}

String localDatabaseFieldLabel(String name) => switch (name) {
  'id' => 'Record ID',
  'action' => 'Action',
  'patientId' => 'Patient ID',
  'timestamp' => 'Timestamp',
  'firebase_uid' || 'uid' => 'Firebase UID',
  'patient_id' => 'Patient ID',
  'history_id' => 'History ID',
  'medication_id' => 'Medication ID',
  'medicationId' => 'Medication ID',
  'medicationName' => 'Medication name',
  'moodIndex' => 'Mood index',
  'moodLabel' => 'Mood',
  'emoji' => 'Emoji',
  'snoozeUntil' => 'Snooze until',
  'syncStatus' => 'Sync status',
  'caregiver_id' => 'Caregiver ID',
  'current_stock' => 'Current stock',
  'days_json' => 'Schedule days',
  'image_url' => 'Image URL',
  'interval_days' => 'Interval days',
  'patient_name' => 'Patient name',
  'remind_refill' => 'Refill reminder enabled',
  'remind_threshold' => 'Refill reminder threshold',
  'remind_before' => 'Reminder minutes before',
  'start_date' => 'Start date',
  'timezone' => 'Time zone',
  'ic_number' => 'IC number',
  'profile_pic_url' => 'Profile image URL',
  'date_of_birth' => 'Date of birth',
  'created_at' => 'Created at',
  'updated_at' => 'Updated at',
  'medical_history' => 'Medical history',
  _ =>
    name.isEmpty
        ? name
        : '${name[0].toUpperCase()}${name.substring(1).replaceAll('_', ' ')}',
};

/// Read-only device-wide inspection, explicitly available to signed-in users.
/// Reuses the app database; never copies profiles or writes to Firebase/SQLite.
class LocalDatabaseOverviewService {
  LocalDatabaseOverviewService({
    CaregiverSqliteService? database,
    String? Function()? currentUid,
    Stream<String?>? uidChanges,
  }) : _database = database ?? CaregiverSqliteService.instance,
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _uidChanges = uidChanges;

  final CaregiverSqliteService _database;
  final String? Function() _currentUid;
  final Stream<String?>? _uidChanges;
  Stream<String?> get uidChanges =>
      _uidChanges ??
      FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);

  void _checkSession(String uid) {
    if (uid.trim().isEmpty || _currentUid() != uid) {
      throw StateError('Sign in to view the local database.');
    }
  }

  Future<LocalDatabaseOverview> load(String uid) async {
    _checkSession(uid);
    final db = await _database.database;
    _checkSession(uid);
    final overview = await db.transaction((txn) async {
      final version = await txn.rawQuery('PRAGMA user_version');
      final names = await txn.rawQuery('''
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
          AND name != 'android_metadata'
        ORDER BY CASE name
          WHEN 'caregivers' THEN 0 WHEN 'patients' THEN 1
          WHEN 'patient_medical_history' THEN 2 ELSE 3 END, name
      ''');
      final tables = <LocalDatabaseTable>[];
      for (final entry in names) {
        final name = entry['name'] as String;
        // Names come from SQLite, and are quoted as identifiers, never SQL input.
        final identifier = '"${name.replaceAll('"', '""')}"';
        final columns = await txn.rawQuery('PRAGMA table_info($identifier)');
        final foreignKeys = await txn.rawQuery(
          'PRAGMA foreign_key_list($identifier)',
        );
        final primaryKeys =
            columns.where((column) => (column['pk'] as int) > 0).toList()
              ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
        final order = primaryKeys.isEmpty
            ? ''
            : ' ORDER BY ${primaryKeys.map((column) => '"${(column['name'] as String).replaceAll('"', '""')}"').join(', ')}';
        final rows = await txn.rawQuery('SELECT * FROM $identifier$order');
        tables.add(
          LocalDatabaseTable(
            name: name,
            columns: columns.map((column) {
              final links = foreignKeys.where(
                (key) => key['from'] == column['name'],
              );
              return LocalDatabaseColumn(
                name: column['name'] as String,
                type: column['type'] as String,
                primaryKey: (column['pk'] as int) > 0,
                requiredValue:
                    column['notnull'] == 1 || (column['pk'] as int) > 0,
                references: links.isEmpty
                    ? null
                    : '${links.first['table']}.${links.first['to']}',
              );
            }).toList(),
            rows: rows,
          ),
        );
      }
      return LocalDatabaseOverview(
        version: version.single['user_version'] as int,
        tables: tables,
      );
    });
    _checkSession(uid);
    return overview;
  }
}
