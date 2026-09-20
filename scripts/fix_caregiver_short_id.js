/**
 * Fixes the caregiver account whose display ID is "CG-QOJ1" so it matches the
 * numeric format every new account gets (e.g. CG-1234 / PH-1234).
 *
 * New caregiver accounts are created with a numeric `shortId` like "CG-2481"
 * (see UserModel.generateId in lib/models/user_model.dart). This account has no
 * `shortId`, so it falls back to a UID-derived id ("CG-QOJ1") and looks
 * different from every other account.
 *
 * This script finds that account and assigns a brand-new numeric shortId that
 * is not already in use. Existing values for every other account are untouched.
 * It is idempotent and safe to re-run.
 *
 * Usage:
 *   cd scripts
 *   set FIREBASE_SERVICE_ACCOUNT=path\to\serviceAccountKey.json
 *   node fix_caregiver_short_id.js            # writes changes
 *   node fix_caregiver_short_id.js --dry-run  # preview only
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

const TARGET_OLD_ID = 'CG-QOJ1';

/** Mirrors UserModel._deriveShortId in lib/models/user_model.dart. */
function deriveShortId(uid, role) {
  const suffix =
    uid.length > 4 ? uid.substring(uid.length - 4).toUpperCase() : uid.toUpperCase();
  const prefix =
    role === 'pharmacist' ? 'PH' : role === 'family' ? 'FM' : role === 'patient' ? 'PT' : 'CG';
  return `${prefix}-${suffix}`;
}

/** Mirrors UserModel.generateId for the caregiver role. */
function randomNumericId() {
  return 1000 + Math.floor(Math.random() * 9000);
}

async function fetchAll(collectionPath, query) {
  const results = [];
  let last = null;
  for (;;) {
    let q = db.collection(collectionPath).limit(BATCH_SIZE);
    if (query) q = q.where(...query);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) results.push(doc);
    last = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < BATCH_SIZE) break;
  }
  return results;
}

async function buildTargetSnapshot() {
  const caregivers = await fetchAll('users', ['role', '==', 'caregiver']);

  const targets = [];
  for (const doc of caregivers) {
    const data = doc.data();
    const shortId = data.shortId || null;
    if (shortId != null && shortId !== TARGET_OLD_ID) continue;
    const derived = deriveShortId(doc.id, 'caregiver');
    if (shortId !== TARGET_OLD_ID && derived !== TARGET_OLD_ID) continue;
    targets.push({ id: doc.id, data });
  }
  return targets;
}

async function collectUsedShortIds() {
  const used = new Set();
  const users = await fetchAll('users', null);
  for (const doc of users) {
    const shortId = doc.data().shortId;
    if (typeof shortId === 'string' && shortId.length > 0) used.add(shortId);
  }
  return used;
}

function nextFreeCaregiverId(used) {
  for (let i = 0; i < 100; i++) {
    const id = `CG-${randomNumericId()}`;
    if (!used.has(id)) return id;
  }
  throw new Error('Could not generate a unique CG-XXXX id after 100 attempts.');
}

async function main() {
  console.log(`${IS_DRY_RUN ? '[DRY RUN] ' : ''}Scanning caregiver accounts...`);
  const targets = await buildTargetSnapshot();

  if (targets.length === 0) {
    console.log(`No caregiver account matches ${TARGET_OLD_ID}. Nothing to do.`);
    return;
  }

  console.log(`Found ${targets.length} matching account(s):`);
  for (const { id, data } of targets) {
    console.log(`  - ${id} (${data.name || 'unnamed'})`);
  }

  const used = await collectUsedShortIds();
  const jobs = targets.map(({ id, data }) => ({
    id,
    data,
    shortId: nextFreeCaregiverId(used),
  }));

  console.log(
    `${IS_DRY_RUN ? 'Would assign' : 'Assigning'} shortId:`,
  );
  for (const { id, data, shortId } of jobs) {
    console.log(`  - ${id} (${data.name || 'unnamed'}): ${TARGET_OLD_ID} -> ${shortId}`);
  }

  if (IS_DRY_RUN) {
    console.log('No changes written (dry run).');
    return;
  }

  for (let i = 0; i < jobs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const job of jobs.slice(i, i + BATCH_SIZE)) {
      batch.update(db.collection('users').doc(job.id), { shortId: job.shortId });
    }
    await batch.commit();
    console.log(`Committed batch ${i / BATCH_SIZE + 1}.`);
  }

  console.log(`Done. Updated ${jobs.length} caregiver account(s).`);
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});