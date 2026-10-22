import 'package:sqflite/sqflite.dart';

/// Device cache and the durable medication-action outbox.
///
/// Account keys are local to this database. Firebase Auth UIDs identify people
/// across devices; business-record integers match their Firestore document keys.
class ClinicalLocalSchema {
  static const version = 18;
  static const databaseName = 'medicare_v18.db';

  static const definitions = [
    '''CREATE TABLE Caregivers (
      caregiver_id INTEGER PRIMARY KEY AUTOINCREMENT,
      uid TEXT NOT NULL UNIQUE CHECK(length(trim(uid)) > 0),
      name TEXT NOT NULL, email TEXT NOT NULL, phone TEXT, profile_pic_url TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE Patients (
      patient_id INTEGER PRIMARY KEY AUTOINCREMENT,
      caregiver_id INTEGER REFERENCES Caregivers(caregiver_id) ON UPDATE CASCADE ON DELETE SET NULL,
      caregiver_uid TEXT,
      uid TEXT NOT NULL UNIQUE CHECK(length(trim(uid)) > 0),
      name TEXT, ic_number TEXT, gender TEXT, email TEXT, phone TEXT,
      date_of_birth TEXT, address TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE Patient_Medical_History (
      history_id INTEGER PRIMARY KEY AUTOINCREMENT,
      patient_id INTEGER NOT NULL REFERENCES Patients(patient_id) ON UPDATE CASCADE ON DELETE CASCADE,
      medical_history TEXT NOT NULL, created_at TEXT NOT NULL,
      UNIQUE (patient_id, medical_history))''',
    '''CREATE TABLE Family_members (
      family_id INTEGER PRIMARY KEY AUTOINCREMENT,
      uid TEXT NOT NULL UNIQUE CHECK(length(trim(uid)) > 0),
      caregiver_id INTEGER REFERENCES Caregivers(caregiver_id) ON UPDATE CASCADE ON DELETE SET NULL,
      caregiver_uid TEXT,
      name TEXT, email TEXT, phone TEXT, relationship TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE Patient_Family_Links (
      family_id INTEGER NOT NULL REFERENCES Family_members(family_id) ON UPDATE CASCADE ON DELETE CASCADE,
      patient_id INTEGER NOT NULL REFERENCES Patients(patient_id) ON UPDATE CASCADE ON DELETE CASCADE,
      PRIMARY KEY (family_id, patient_id))''',
    '''CREATE TABLE Pharmacists (
      pharmacy_id INTEGER PRIMARY KEY AUTOINCREMENT,
      uid TEXT NOT NULL UNIQUE CHECK(length(trim(uid)) > 0),
      caregiver_id INTEGER REFERENCES Caregivers(caregiver_id) ON UPDATE CASCADE ON DELETE SET NULL,
      caregiver_uid TEXT,
      name TEXT, email TEXT, phone TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE Medications (
      medication_id INTEGER PRIMARY KEY CHECK(medication_id > 0 AND medication_id <= 9007199254740991))''',
    '''CREATE TABLE Appointments (
      appointment_id INTEGER PRIMARY KEY CHECK(appointment_id > 0 AND appointment_id <= 9007199254740991))''',
    '''CREATE TABLE Medication_Schedule (
      patient_id INTEGER NOT NULL REFERENCES Patients(patient_id) ON UPDATE CASCADE ON DELETE CASCADE,
      medication_id INTEGER NOT NULL UNIQUE REFERENCES Medications(medication_id),
      caregiver_id INTEGER REFERENCES Caregivers(caregiver_id) ON UPDATE CASCADE ON DELETE SET NULL,
      caregiver_uid TEXT NOT NULL,
      patient_name TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL,
      days_json TEXT NOT NULL, dosage TEXT NOT NULL, time TEXT NOT NULL,
      timezone TEXT NOT NULL, start_date TEXT,
      remind_refill INTEGER NOT NULL CHECK(remind_refill IN (0, 1)),
      remind_threshold INTEGER NOT NULL CHECK(remind_threshold >= 0),
      current_stock INTEGER NOT NULL CHECK(current_stock >= 0),
      interval_days INTEGER NOT NULL CHECK(interval_days > 0), image_url TEXT,
      PRIMARY KEY (patient_id, medication_id))''',
    '''CREATE TABLE Appointment_Schedules (
      patient_id INTEGER NOT NULL REFERENCES Patients(patient_id) ON UPDATE CASCADE ON DELETE CASCADE,
      appointment_id INTEGER NOT NULL UNIQUE REFERENCES Appointments(appointment_id),
      caregiver_id INTEGER REFERENCES Caregivers(caregiver_id) ON UPDATE CASCADE ON DELETE SET NULL,
      caregiver_uid TEXT NOT NULL,
      patient_name TEXT NOT NULL, title TEXT NOT NULL, date TEXT NOT NULL,
      time TEXT NOT NULL, location TEXT NOT NULL,
      remind_before INTEGER NOT NULL CHECK(remind_before >= 0),
      status TEXT NOT NULL CHECK(status IN ('scheduled', 'completed')),
      PRIMARY KEY (patient_id, appointment_id))''',
    '''CREATE TABLE Medication_Action (
      id INTEGER PRIMARY KEY CHECK(id > 0 AND id <= 9007199254740991),
      medication_id INTEGER NOT NULL REFERENCES Medications(medication_id),
      medication_name TEXT NOT NULL,
      patient_id INTEGER NOT NULL REFERENCES Patients(patient_id) ON UPDATE CASCADE ON DELETE CASCADE,
      action TEXT NOT NULL CHECK(action IN ('taken', 'skipped', 'snoozed')),
      timestamp INTEGER NOT NULL CHECK(timestamp >= 0), snooze_until INTEGER,
      sync_status TEXT NOT NULL CHECK(sync_status IN ('pending', 'synced')))''',
    '''CREATE TABLE Mood (
      id INTEGER PRIMARY KEY CHECK(id > 0 AND id <= 9007199254740991),
      patient_id INTEGER NOT NULL REFERENCES Patients(patient_id) ON UPDATE CASCADE ON DELETE CASCADE,
      mood_index INTEGER NOT NULL CHECK(mood_index BETWEEN 0 AND 8),
      mood_label TEXT NOT NULL, emoji TEXT NOT NULL, date TEXT NOT NULL,
      timestamp INTEGER NOT NULL CHECK(timestamp >= 0))''',
    '''CREATE TABLE Refill_Request (
      id INTEGER PRIMARY KEY CHECK(id > 0 AND id <= 9007199254740991),
      caregiver_id INTEGER REFERENCES Caregivers(caregiver_id) ON UPDATE CASCADE ON DELETE SET NULL,
      caregiver_uid TEXT NOT NULL,
      pharmacy_id INTEGER REFERENCES Pharmacists(pharmacy_id) ON UPDATE CASCADE ON DELETE SET NULL,
      pharmacy_uid TEXT,
      patient_id INTEGER NOT NULL REFERENCES Patients(patient_id) ON UPDATE CASCADE ON DELETE CASCADE,
      medication_id INTEGER NOT NULL REFERENCES Medications(medication_id),
      caregiver_name TEXT NOT NULL, patient_name TEXT NOT NULL,
      medication_name TEXT NOT NULL,
      quantity_left INTEGER NOT NULL CHECK(quantity_left >= 0),
      quantity_requested INTEGER NOT NULL CHECK(quantity_requested >= 0),
      status TEXT NOT NULL CHECK(status IN ('pending', 'processing', 'ready_for_pickup', 'collected', 'rejected')),
      requested_at INTEGER NOT NULL CHECK(requested_at >= 0), updated_at INTEGER)''',
  ];

  static Future<void> create(DatabaseExecutor db) async {
    for (final sql in definitions) {
      await db.execute(sql);
    }
    for (final sql in const [
      'CREATE INDEX patients_caregiver ON Patients(caregiver_id)',
      'CREATE INDEX patients_caregiver_uid ON Patients(caregiver_uid)',
      'CREATE INDEX family_caregiver_uid ON Family_members(caregiver_uid)',
      'CREATE INDEX pharmacists_caregiver_uid ON Pharmacists(caregiver_uid)',
      'CREATE INDEX patient_family_links_patient ON Patient_Family_Links(patient_id)',
      'CREATE INDEX medication_schedule_caregiver ON Medication_Schedule(caregiver_id)',
      'CREATE INDEX medication_schedule_caregiver_uid ON Medication_Schedule(caregiver_uid)',
      'CREATE INDEX appointment_schedule_caregiver ON Appointment_Schedules(caregiver_id)',
      'CREATE INDEX appointment_schedule_caregiver_uid ON Appointment_Schedules(caregiver_uid)',
      'CREATE INDEX medication_action_patient_timestamp ON Medication_Action(patient_id, timestamp DESC)',
      'CREATE INDEX medication_action_outbox ON Medication_Action(patient_id, sync_status, timestamp)',
      'CREATE INDEX medication_action_medication ON Medication_Action(medication_id)',
      'CREATE INDEX mood_patient_date_timestamp ON Mood(patient_id, date, timestamp DESC)',
      'CREATE INDEX refill_request_caregiver_date ON Refill_Request(caregiver_uid, requested_at DESC)',
      'CREATE INDEX refill_request_patient ON Refill_Request(patient_id)',
      'CREATE INDEX refill_request_medication ON Refill_Request(medication_id)',
      'CREATE INDEX refill_request_pharmacy ON Refill_Request(pharmacy_id)',
      'CREATE INDEX refill_request_pharmacy_uid ON Refill_Request(pharmacy_uid)',
    ]) {
      await db.execute(sql);
    }
  }
}
