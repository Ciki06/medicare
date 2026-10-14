'use strict';
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {randomInt} = require('node:crypto');
const {ROLES, RECORDS, validId} = require('./shared_record_ids');
const db = admin.firestore();
const region = functions.region('asia-southeast1');
const ALLOCATORS = Object.freeze({medications:['caregiver'], appointments:['caregiver'], medication_actions:['patient'], moods:['patient'], refill_requests:['caregiver','patient']});

// Exact JavaScript/Firestore/SQLite integers. Randomness allows disconnected
// devices to allocate IDs without a counter or reservation collection.
function newId() {
  return 2 ** 52 + randomInt(2 ** 26) * 2 ** 26 + randomInt(2 ** 26);
}

exports.reserveRecordIds = region.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) throw new functions.https.HttpsError('unauthenticated','Sign in to continue.');
  const entity = data?.entity;
  const count = data?.count;
  const profile = (await db.doc(`users/${uid}`).get()).data();
  if (!ALLOCATORS[entity]?.includes(profile?.role)) throw new functions.https.HttpsError('permission-denied','This account cannot allocate those records.');
  if (!Number.isInteger(count) || count < 1 || count > 256) throw new functions.https.HttpsError('invalid-argument','Invalid record count.');
  // Compatibility for an already running previous app version. New apps mint
  // individual IDs locally. Neither path creates bookkeeping documents.
  for (let attempt=0; attempt<10; attempt++) {
    const start = Math.floor(newId()/256)*256, end = start+count-1;
    const existing = await db.collection(entity).where('id','>=',start).where('id','<=',end).limit(1).get();
    if (existing.empty) return {start,end};
  }
  throw new functions.https.HttpsError('unavailable','Try allocating IDs again.');
});

exports.saveAccountProfile = region.https.onCall(async (data, context) => {
  const caller = context.auth?.uid;
  const uid = data?.uid;
  const role = data?.role;
  if (!caller) throw new functions.https.HttpsError('unauthenticated','Sign in to continue.');
  if (typeof uid !== 'string' || !uid || !ROLES[role]) throw new functions.https.HttpsError('invalid-argument','Invalid account profile.');
  const caregiverUid = data.caregiver_uid || data.caregiverId;
  const callerProfile = (await db.doc(`users/${caller}`).get()).data();
  if (caller !== uid && !(callerProfile?.role === 'caregiver' && caregiverUid === caller && role !== 'caregiver')) throw new functions.https.HttpsError('permission-denied','Only your own or your managed account can be created.');
  const authUser = await admin.auth().getUser(uid);
  const values = {uid,role,email:authUser.email || data.email};
  for (const field of ['name','createdAt','phone','dateOfBirth','gender','address','registeredId','icNumber','medicalHistory','medicalNotes','profilePicUrl','shortId','linkedPatientEmails']) {
    if (data[field] != null) values[field] = data[field];
  }
  if (caregiverUid) {
    const caregiver = (await db.doc(`users/${caregiverUid}`).get()).data();
    if (caregiver?.role !== 'caregiver' || !validId(caregiver.id)) throw new functions.https.HttpsError('failed-precondition','Caregiver identity is not ready.');
    values.caregiverId = caregiver.id; values.caregiver_uid = caregiverUid;
  }
  const linkedUids = data.linkedPatientUids || data.linkedPatientIds || [];
  if (!Array.isArray(linkedUids) || linkedUids.some(item=>typeof item!=='string')) throw new functions.https.HttpsError('invalid-argument','Invalid patient links.');
  if (linkedUids.length) {
    const linked = await db.getAll(...linkedUids.map(item=>db.doc(`users/${item}`)));
    if (linked.some(item=>item.data()?.role!=='patient'||!validId(item.data()?.id)||(caller!==uid&&item.data().caregiver_uid!==caller))) throw new functions.https.HttpsError('permission-denied','Invalid managed patient relationship.');
    values.linkedPatientIds=linked.map(item=>item.data().id); values.linkedPatientUids=linkedUids;
  }
  return db.runTransaction(async transaction => {
    const target=db.doc(`users/${uid}`);
    const existing=await transaction.get(target);
    if (existing.exists) {
      if (existing.data().role !== role) throw new functions.https.HttpsError('already-exists','Account role cannot be changed.');
      if (validId(existing.data().id)) return existing.data();
    }
    do {
      values.id=newId();
    } while (!(await transaction.get(db.collection('users').where('id','==',values.id).limit(1))).empty);
    transaction.set(target,values,{merge:true});
    return values;
  });
});

// Deleted schedules remain valid foreign keys for that patient's history.
// Store just the retired relationship on the existing patient profile.
exports.retainMedicationIdentity = region.firestore.document('medications/{id}').onWrite(async (change, context) => {
    const data = change.after.exists ? change.after.data() : change.before.data();
    if (!validId(data?.id) || String(data.id) !== context.params.id || !data.patient_uid) return null;
    // Trigger delivery can arrive out of order. Read the current schedule in
    // the transaction so an old update cannot erase a later deletion's ID.
    await db.runTransaction(async transaction => {
      const current = await transaction.get(db.doc(`medications/${context.params.id}`));
      const patientRef = db.doc(`users/${data.patient_uid}`);
      const patient = await transaction.get(patientRef);
      if (!patient.exists || patient.data().role !== 'patient') return;
      const values = {retiredMedicationIds: current.exists
          ? admin.firestore.FieldValue.arrayRemove(data.id)
          : admin.firestore.FieldValue.arrayUnion(data.id)};
      transaction.update(patientRef, values);
    });
    return null;
});

function collectMappings(users, records) {
  const maps = Object.fromEntries([...Object.values(ROLES),...RECORDS].map(entity=>[entity,{}]));
  for (const user of users) {
    if (ROLES[user.data.role] && validId(user.data.id)) maps[ROLES[user.data.role]][user.uid]=user.data.id;
    for (const id of user.data.retiredMedicationIds || []) if (validId(id)) maps.medications[String(id)]=id;
  }
  for (const [entity,documents] of Object.entries(records)) for (const doc of documents) {
    if (validId(doc.data.id)) maps[entity][doc.data.legacy_uid || doc.uid]=doc.data.id;
    if (validId(doc.data.medicationId)) maps.medications[doc.data.legacy_medication_uid || String(doc.data.medicationId)]=doc.data.medicationId;
  }
  // Prefer a legacy alias when one exists. Numeric keys resolve directly in
  // SQLite; one alias per ID also keeps older migration code compatible.
  for (const mapping of Object.values(maps)) {
    const legacyIds=new Set(Object.entries(mapping).filter(([uid])=>!/^\d+$/.test(uid)).map(([,id])=>id));
    for (const [uid,id] of Object.entries(mapping)) if (/^\d+$/.test(uid) && legacyIds.has(id)) delete mapping[uid];
  }
  return maps;
}

exports.getRecordIdentities = region.https.onCall(async (_data, context) => {
  const uid=context.auth?.uid;
  if (!uid) throw new functions.https.HttpsError('unauthenticated','Sign in to continue.');
  const usersSnapshot=await db.collection('users').get();
  const users=usersSnapshot.docs.map(doc=>({uid:doc.id,data:doc.data()}));
  const caller=users.find(doc=>doc.uid===uid)?.data;
  if (!ROLES[caller?.role]) throw new functions.https.HttpsError('permission-denied','Account profile is missing.');
  const caregiver=caller.role==='caregiver'?uid:caller.caregiver_uid;
  const linked=new Set([...(caller.linkedPatientUids || []),caller.linkedPatientUid].filter(Boolean));
  const patients=users.filter(doc=>doc.data.role==='patient' &&
    (caller.role==='patient'?doc.uid===uid:(doc.data.caregiver_uid===caregiver && !!caregiver) || (caller.role==='family' && linked.has(doc.uid)))).map(doc=>doc.uid);
  const records={};
  for (const entity of RECORDS) {
    if (caller.role==='family' && entity==='refill_requests') continue;
    const documents=new Map();
    if (caller.role==='pharmacist' && entity==='refill_requests') {
      for (const doc of (await db.collection(entity).get()).docs) documents.set(doc.id,doc);
    } else {
      for (let i=0;i<patients.length;i+=30) {
        const snapshot=await db.collection(entity).where('patient_uid','in',patients.slice(i,i+30)).get();
        for (const doc of snapshot.docs) documents.set(doc.id,doc);
      }
    }
    records[entity]=[...documents.values()].map(doc=>({uid:doc.id,data:doc.data()}));
  }
  return {mappings:collectMappings(users,records)};
});
exports._test = {ALLOCATORS,newId,collectMappings};
