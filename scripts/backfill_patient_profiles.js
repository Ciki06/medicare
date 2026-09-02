/**
 * Backfills the new patient profile fields onto every existing patient
 * account in Firestore.
 *
 * Fields added by the "Update Patient Profile Details" change:
 *   - medicalHistory      -> [] when missing
 *   - shortId             -> deterministic PT-xxx when missing
 *   - dateOfBirth         -> derived from icNumber when derivable and missing
 *
 * Existing values are never overwritten. This script is idempotent, so it is
 * safe to re-run.
 *
 * Usage:
 *   cd scripts
 *   npm install
 *   set FIREBASE_SERVICE_ACCOUNT=path\to\serviceAccountKey.json
 *   node backfill_patient_profiles.js            # writes changes
 *   node backfill_patient_profiles.js --dry-run  # preview only
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const IS_DRY_RUN = process.argv.includes('--dry-run');

const KEY_PATH =
  process.env.FIREBASE_SERVICE_ACCOUNT ||
  path.join(__dirname, 'serviceAccountKey.json');

if (!fs.existsSync(KEY_PATH)) {
  console.error(
    'Service account key not found. Set FIREBASE_SERVICE_ACCOUNT to the path ' +
      'of your Firebase service-account JSON (Project settings > Service accounts > ' +
      'Generate new private key).',
  );
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(KEY_PATH),
});

const db = admin.firestore();
const BATCH_SIZE = 400;

/** Mirrors MalaysianIc.format in lib/models/malaysian_ic.dart. */
function formatIc(raw) {
  const digits = (raw || '').replace(/\D/g, '');
  const s = digits.length > 12 ? digits.substring(0, 12) : digits;
  const a = s.length > 6 ? s.substring(0, 6) : s;
  const b = s.length > 8 ? s.substring(6, 8) : s.length > 6 ? s.substring(6) : '';
  const c = s.length > 8 ? s.substring(8) : '';
  return [a, b, c].filter((p) => p.length > 0).join('-');
}

/** Parses the YYMMDD part; returns a Date or null. Mirrors MalaysianIc.birthDate. */
function birthDate(value) {
  const digits = (value || '').replace(/\D/g, '');
  if (digits.length !== 12) return null;
  const m = /^(\d{2})(\d{2})(\d{2})-(\d{2})-(\d{4})$/.exec(formatIc(digits));
  if (!m) return null;
  const yy = parseInt(m[1], 10);
  const month = parseInt(m[2], 10);
  const day = parseInt(m[3], 10);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  const currentYY = new Date().getFullYear() % 100;
  const year = (yy > currentYY ? 1900 : 2000) + yy;
  const d = new Date(Date.UTC(year, month - 1, day));
  if (
    d.getUTCFullYear() !== year ||
    d.getUTCMonth() !== month - 1 ||
    d.getUTCDate() !== day
  ) {
    return null;
  }
  return d;
}

/** Mirrors MalaysianIc.dateOfBirth (DD/MM/YYYY). */
function dateOfBirth(value) {
  const d = birthDate(value);
  if (!d) return null;
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
}

/** Mirrors UserModel._deriveShortId for the patient role. */
function deriveShortId(uid, role) {
  const suffix =
    uid.length > 8 ? uid.substring(uid.length - 8).toUpperCase() : uid.toUpperCase();
  const prefix =
    role === 'caregiver'
      ? 'CG'
      : role === 'family'
        ? 'FM'
        : role === 'pharmacist'
          ? 'PH'
          : 'PT';
  return `${prefix}-${suffix}`;
}

function buildUpdates(snap) {
  const data = snap.data();
  const uid = snap.id;
  const updates = {};

  if (!Array.isArray(data.medicalHistory)) {
    updates.medicalHistory = [];
  }
  if (!data.shortId) {
    updates.shortId = deriveShortId(uid, data.role === 'patient' ? 'patient' : data.role);
  }
  if (!data.dateOfBirth && data.icNumber) {
    const dob = dateOfBirth(data.icNumber);
    if (dob) updates.dateOfBirth = dob;
  }

  return updates;
}

async function fetchAllPatients() {
  const patients = [];
  let last = null;
  for (;;) {
    let query = db.collection('users').where('role', '==', 'patient').limit(BATCH_SIZE);
    if (last) query = query.startAfter(last);
    const snap = await query.get();
    if (snap.empty) break;
    for (const doc of snap.docs) patients.push(doc);
    last = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < BATCH_SIZE) break;
  }
  return patients;
}

async function main() {
  console.log(`${IS_DRY_RUN ? '[DRY RUN] ' : ''}Scanning patient accounts...`);
  const patients = await fetchAllPatients();
  console.log(`Found ${patients.length} patient account(s).`);

  const jobs = [];
  for (const doc of patients) {
    const updates = buildUpdates(doc);
    if (Object.keys(updates).length > 0) {
      jobs.push({ id: doc.id, data: doc.data(), updates });
    }
  }

  if (jobs.length === 0) {
    console.log('All patient accounts already have the new profile fields.');
    return;
  }

  console.log(
    `${IS_DRY_RUN ? 'Would update' : 'Updating'} ${jobs.length} account(s):`,
  );
  for (const { id, data, updates } of jobs) {
    console.log(
      `  - ${id} (${data.name || 'unnamed'}): ${Object.keys(updates).join(', ')}`,
    );
  }

  if (IS_DRY_RUN) {
    console.log('No changes written (dry run).');
    return;
  }

  for (let i = 0; i < jobs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const job of jobs.slice(i, i + BATCH_SIZE)) {
      batch.update(db.collection('users').doc(job.id), job.updates);
    }
    await batch.commit();
    console.log(`Committed batch ${i / BATCH_SIZE + 1}.`);
  }

  console.log(`Done. Updated ${jobs.length} patient account(s).`);
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});