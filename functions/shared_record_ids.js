'use strict';

const ROLES = Object.freeze({caregiver: 'caregivers', patient: 'patients', family: 'family_members', pharmacist: 'pharmacists'});
const RECORDS = ['medications', 'appointments', 'medication_actions', 'moods', 'refill_requests'];

function validId(value) { return Number.isSafeInteger(value) && value > 0; }
function allocate(docs, field = 'id') {
  const result = new Map(), used = new Set();
  for (const doc of docs) {
    const id = doc.data[field];
    if (!validId(id)) continue;
    if (used.has(id)) throw new Error(`Duplicate canonical ID ${id}.`);
    used.add(id); result.set(doc.uid, id);
  }
  let next = 1;
  for (const doc of [...docs].sort((a, b) => a.uid.localeCompare(b.uid))) {
    if (result.has(doc.uid)) continue;
    while (used.has(next)) next++;
    result.set(doc.uid, next); used.add(next++);
  }
  return result;
}

// Pure, deterministic planning: no network calls or destructive mutations.
// All lookups use complete collection snapshots, including deleted-medication
// references retained in history. A missing user stops the entire migration.
function planAlignment(snapshot) {
  const source = snapshot.collections;
  const users = new Map((source.users || []).map(doc => [doc.uid, doc]));
  const roleMaps = {};
  for (const [role, table] of Object.entries(ROLES)) {
    roleMaps[table] = allocate([...users.values()].filter(doc => doc.data.role === role));
  }
  function userId(uid, role) {
    const doc = users.get(uid);
    if (!doc || (role && doc.data.role !== role)) throw new Error(`Missing ${role || 'user'} relationship for ${uid}.`);
    const table = ROLES[doc.data.role];
    if (!table) throw new Error(`Unsupported user role ${doc.data.role}.`);
    return roleMaps[table].get(uid);
  }
  const mappings = Object.fromEntries(RECORDS.map(name => [name, allocate(source[name] || [])]));
  // Medication identities are retained independently of active schedules.
  const medicationSources = [...(source.medications || [])];
  const seenMedications = new Set(medicationSources.map(doc => doc.uid));
  for (const name of ['medication_actions', 'refill_requests']) for (const doc of source[name] || []) {
    const uid = doc.data.medication_uid || (doc.data.medicationId == null ? null : String(doc.data.medicationId));
    if (typeof uid === 'string' && uid && !seenMedications.has(uid)) {
      const numeric = /^\d+$/.test(uid) ? Number(uid) : null;
      medicationSources.push({uid, data: validId(numeric) ? {id:numeric} : {}}); seenMedications.add(uid);
    }
  }
  mappings.medications = allocate(medicationSources);
  const writes = [], moves = [];
  function relations(data) {
    const converted = {...data};
    for (const [field, uidField, role] of [['patientId', 'patient_uid', 'patient'], ['caregiverId', 'caregiver_uid', 'caregiver']]) {
      const uid = data[uidField] || (typeof data[field] === 'string' ? data[field] : null);
      if (!uid) {
        if (data[field] != null && !validId(data[field])) throw new Error(`Invalid ${field}.`);
        continue;
      }
      converted[field] = userId(uid, role); converted[uidField] = uid;
    }
    const medicationUid = data.medication_uid || (typeof data.medicationId === 'string' ? data.medicationId : null);
    if (medicationUid) {
      const id = mappings.medications.get(medicationUid);
      if (!id) throw new Error('Medication reference is missing.');
      converted.medicationId = id; converted.medication_uid = String(id);
    }
    return converted;
  }
  for (const doc of users.values()) {
    const id = userId(doc.uid);
    const data = relations({...doc.data, id, uid: doc.uid});
    const linkedUids = doc.data.linkedPatientUids || doc.data.linkedPatientIds || (doc.data.linkedPatientId ? [doc.data.linkedPatientId] : []);
    if (linkedUids.length) {
      data.linkedPatientUids = linkedUids;
      data.linkedPatientIds = linkedUids.map(uid => userId(uid, 'patient'));
      const singleUid = doc.data.linkedPatientUid || (typeof doc.data.linkedPatientId === 'string' ? doc.data.linkedPatientId : null);
      if (singleUid) {
        data.linkedPatientUid = singleUid;
        data.linkedPatientId = userId(singleUid, 'patient');
      }
    }
    // Authentication profiles keep their UID address; their business ID is
    // the integer primary key of the corresponding SQLite role table.
    writes.push({collection: 'users', document: doc.uid, original: doc.uid, data});
  }
  for (const collection of RECORDS) for (const doc of source[collection] || []) {
    const id = mappings[collection].get(doc.uid);
    const data = relations({...doc.data, id, uid: String(id), legacy_uid: doc.data.legacy_uid || doc.uid});
    writes.push({collection, document: String(id), original: doc.uid, data});
    if (doc.uid !== String(id)) moves.push({collection, from: doc.uid, to: String(id), updateTime: doc.updateTime});
  }
  const activeMedicationUids = new Set((source.medications || []).map(doc => doc.uid));
  const archivedMedicationIds = [...mappings.medications].filter(([uid]) => !activeMedicationUids.has(uid)).map(([,id]) => id).sort((a,b) => a-b);
  const counters = {};
  for (const [name, map] of Object.entries({...roleMaps, ...mappings})) counters[name] = Math.max(0, ...map.values());
  const serializable = map => Object.fromEntries(map);
  return {version: 2, projectId: snapshot.projectId, writes, moves, counters, archivedMedicationIds,
    mappings: Object.fromEntries(Object.entries({...roleMaps, ...mappings}).map(([name, map]) => [name, serializable(map)]))};
}

module.exports = {ROLES, RECORDS, validId, allocate, planAlignment};
