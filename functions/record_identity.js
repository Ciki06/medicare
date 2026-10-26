'use strict';

// Authentication UIDs are the sole user relationship keys in Firestore.
// SQLite allocates its own integer profile keys; they never cross this API.
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const db = admin.firestore();
const region = functions.region('asia-southeast1');
const {createManagedProvisioner, managedUid} = require('./account_provisioning');
const provisionManagedAccount = createManagedProvisioner({db,auth:admin.auth()});
const ROLES = new Set(['caregiver', 'patient', 'family', 'pharmacist']);
const TEXT_FIELDS = new Set(['name', 'phone', 'dateOfBirth', 'gender', 'address',
  'registeredId', 'icNumber', 'medicalNotes', 'profilePicUrl', 'shortId', 'relationship']);
const EDITABLE_FIELDS = new Set([...TEXT_FIELDS, 'medicalHistory', 'caregiverId', 'linkedPatientIds']);
const OPTIONAL_FIELDS = new Set([...EDITABLE_FIELDS].filter(field => field !== 'name'));

function fail(code, message) { throw new functions.https.HttpsError(code, message); }
function uidValue(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 128 && !value.includes('/');
}
function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}
function emailValue(value) {
  const email = normalizeEmail(value);
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) fail('invalid-argument', 'Enter a valid email address.');
  return email;
}
function dateOfBirthValue(value) {
  const input = value.trim();
  if (!input) return null;
  let match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(input);
  if (!match) {
    const form = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(input);
    if (form) match = [form[0], form[3], form[2], form[1]];
  }
  if (!match) fail('invalid-argument', 'Enter a valid date of birth.');
  const [, year, month, day] = match;
  const date = new Date(Number(year), Number(month) - 1, Number(day));
  if (date.getFullYear() !== Number(year) || date.getMonth() !== Number(month) - 1 || date.getDate() !== Number(day)) fail('invalid-argument', 'Enter a valid date of birth.');
  return year + '-' + month + '-' + day;
}
function editableValues(source) {
  if (!source || typeof source !== 'object' || Array.isArray(source)) fail('invalid-argument', 'Invalid profile changes.');
  const result = {};
  for (const [field, value] of Object.entries(source)) {
    if (!EDITABLE_FIELDS.has(field)) fail('invalid-argument', 'This profile field cannot be changed.');
    if (value === null) {
      if (!OPTIONAL_FIELDS.has(field)) fail('invalid-argument', 'A name is required.');
      result[field] = null;
    } else if (TEXT_FIELDS.has(field)) {
      if (typeof value !== 'string' || value.length > (field === 'medicalNotes' ? 10000 : 2048) || (field === 'name' && !value.trim())) fail('invalid-argument', 'Invalid profile text.');
      result[field] = field === 'dateOfBirth' ? dateOfBirthValue(value) : value.trim();
    } else if (field === 'caregiverId') {
      if (!uidValue(value)) fail('invalid-argument', 'Invalid caregiver.');
      result[field] = value;
    } else if (field === 'medicalHistory') {
      if (!Array.isArray(value) || value.length > 100 || value.some(item => typeof item !== 'string' || item.length > 500)) fail('invalid-argument', 'Invalid medical history.');
      result[field] = [...new Set(value.map(item => item.trim()).filter(Boolean))];
    } else if (field === 'linkedPatientIds') {
      if (!Array.isArray(value) || value.length > 100 || value.some(item => !uidValue(item))) fail('invalid-argument', 'Invalid patient links.');
      result[field] = [...new Set(value)];
    }
  }
  return result;
}

async function validateRelationships(profile, values) {
  const merged = {...profile, ...values};
  const caregiverId = merged.caregiverId;
  if (caregiverId) {
    const caregiver = await db.doc('users/' + caregiverId).get();
    if (caregiver.data()?.role !== 'caregiver') fail('failed-precondition', 'Caregiver account was not found.');
    if (merged.role === 'caregiver') fail('invalid-argument', 'A caregiver cannot be managed by another caregiver.');
  }
  if ('linkedPatientIds' in values || ('caregiverId' in values && merged.role === 'family')) {
    const ids = merged.linkedPatientIds || [];
    if (merged.role !== 'family' && ids.length) fail('invalid-argument', 'Only family accounts can have patient links.');
    const patients = ids.length ? await db.getAll(...ids.map(uid => db.doc('users/' + uid))) : [];
    if (patients.some(patient => patient.data()?.role !== 'patient' || !caregiverId || patient.data().caregiverId !== caregiverId)) fail('permission-denied', 'Choose patients managed by this caregiver.');
    values.linkedPatientIds = ids;
    values.linkedPatientEmails = patients.map(patient => patient.data().email);
  }
  return values;
}

function managedBy(callerUid, caller, target) {
  return caller?.role === 'caregiver' && target?.caregiverId === callerUid;
}
function samePatientLinks(left, right) {
  const first = [...new Set(left || [])].sort();
  const second = [...new Set(right || [])].sort();
  return first.length === second.length && first.every((uid, index) => uid === second[index]);
}

async function saveAccountProfile(data, context) {
  const callerUid = context.auth?.uid;
  if (!callerUid) fail('unauthenticated', 'Sign in to continue.');
  if (!uidValue(data?.uid) || !ROLES.has(data?.role)) fail('invalid-argument', 'Invalid account profile.');
  const targetUid = data.uid;
  if (callerUid !== targetUid) fail('permission-denied', 'Only your own account can be created here. Use managed account creation for a care-team account.');
  if (targetUid.startsWith('managed_')) fail('permission-denied', 'The managed account profile is created by its caregiver.');
  const authUser = await admin.auth().getUser(targetUid);
  const input = Object.fromEntries(Object.entries(data).filter(([field]) => EDITABLE_FIELDS.has(field)));
  const values = editableValues(input);
  if (!values.name) fail('invalid-argument', 'A name is required.');
  const timestamp = new Date().toISOString();
  const profile = {uid: targetUid, role: data.role, email: emailValue(authUser.email), createdAt: timestamp, updatedAt: timestamp};
  await validateRelationships(profile, values);
  for (const [field, value] of Object.entries(values)) if (value !== null) profile[field] = value;
  return db.runTransaction(async transaction => {
    const reference = db.doc('users/' + targetUid);
    const existing = await transaction.get(reference);
    if (existing.exists) {
      if (existing.data().role !== data.role) fail('already-exists', 'Account role cannot be changed.');
      return existing.data();
    }
    if (['family','pharmacist'].includes(data.role) &&
        (profile.caregiverId != null || (profile.linkedPatientIds || []).length > 0)) {
      fail('permission-denied', 'Ask your caregiver to link this account.');
    }
    transaction.create(reference, profile);
    return profile;
  });
}
exports.saveAccountProfile = region.https.onCall(saveAccountProfile);

exports.createManagedAccount = region.https.onCall(async (data, context) => {
  const callerUid = context.auth?.uid;
  if (!callerUid) fail('unauthenticated', 'Sign in to continue.');
  const caller = (await db.doc('users/' + callerUid).get()).data();
  if (caller?.role !== 'caregiver') fail('permission-denied', 'Only a caregiver can create a managed account.');
  if (!ROLES.has(data?.role) || data.role === 'caregiver' ||
      (data.caregiverId != null && data.caregiverId !== callerUid)) fail('permission-denied', 'Choose a managed account role and your own caregiver relationship.');
  const email = emailValue(data.email);
  managedUid(callerUid,data.requestId);
  if (typeof data.password !== 'string' || data.password.length < 6 || data.password.length > 4096) fail('invalid-argument', 'Use a password with at least six characters.');
  const values = editableValues(Object.fromEntries(Object.entries(data).filter(([field]) => EDITABLE_FIELDS.has(field))));
  if (!values.name) fail('invalid-argument', 'A name is required.');
  values.caregiverId = callerUid;
  await validateRelationships({role:data.role}, values);
  return provisionManagedAccount({callerUid,requestId:data.requestId,email,password:data.password,role:data.role,values});
});

exports.updateAccountProfile = region.https.onCall(async (data, context) => {
  const callerUid = context.auth?.uid;
  if (!callerUid) fail('unauthenticated', 'Sign in to continue.');
  const targetUid = data?.uid || callerUid;
  if (!uidValue(targetUid)) fail('invalid-argument', 'Invalid account.');
  const changes = editableValues(data?.changes);
  const [callerSnap, targetSnap] = await Promise.all([db.doc('users/' + callerUid).get(), db.doc('users/' + targetUid).get()]);
  const caller = callerSnap.data(), target = targetSnap.data();
  if (!target) fail('not-found', 'Account was not found.');
  if (callerUid === targetUid && target.role === 'family' && 'linkedPatientIds' in changes &&
      !samePatientLinks(changes.linkedPatientIds, target.linkedPatientIds)) {
    fail('permission-denied', 'Ask your caregiver to manage patient links.');
  }
  const claiming = caller?.role === 'caregiver' && target.role !== 'caregiver' && !target.caregiverId && changes.caregiverId === callerUid;
  if (callerUid !== targetUid && !managedBy(callerUid, caller, target) && !claiming) fail('permission-denied', 'Only your own account or an account you manage can be changed.');
  if ('caregiverId' in changes && changes.caregiverId !== target.caregiverId && !claiming) fail('permission-denied', 'The caregiver relationship cannot be changed here.');
  await validateRelationships(target, changes);
  const profile = {...target, updatedAt: new Date().toISOString()};
  // Reconcile the authoritative Firebase Auth sign-in address here; clients
  // cannot submit an arbitrary email through profile editing.
  const authAccount = await admin.auth().getUser(targetUid);
  profile.email = emailValue(authAccount.email);
  for (const [field, value] of Object.entries(changes)) {
    if (value === null) delete profile[field];
    else profile[field] = value;
  }
  // A transaction prevents concurrent edits or claims overwriting one another.
  await db.runTransaction(async transaction => {
    const current = await transaction.get(targetSnap.ref);
    if (!current.updateTime.isEqual(targetSnap.updateTime)) fail('aborted', 'The profile changed. Please try again.');
    transaction.set(targetSnap.ref, profile);
  });
  if (target.role === 'patient' && target.email !== profile.email) {
    await require('./accounts')._internal.replaceLinkedPatientEmail(targetUid, target.email, profile.email);
  }
  return {profile};
});

exports.lookupCaregiverByEmail = region.https.onCall(async data => {
  const email = emailValue(data?.email);
  const snapshot = await db.collection('users').where('email', '==', email).where('role', '==', 'caregiver').limit(1).get();
  if (snapshot.empty) return {profile: null};
  const document = snapshot.docs[0], profile = document.data();
  return {profile: {uid: document.id, name: profile.name, email: profile.email, role: 'caregiver', createdAt: profile.createdAt}};
});

exports.lookupUserByEmail = region.https.onCall(async (data, context) => {
  const callerUid = context.auth?.uid;
  if (!callerUid) fail('unauthenticated', 'Sign in to continue.');
  const email = emailValue(data?.email);
  const [callerSnap, matches] = await Promise.all([db.doc('users/' + callerUid).get(), db.collection('users').where('email', '==', email).limit(1).get()]);
  if (matches.empty) return {profile: null};
  const caller = callerSnap.data(), document = matches.docs[0], target = document.data();
  const unassigned = caller?.role === 'caregiver' && target.role !== 'caregiver' && !target.caregiverId;
  const familyPatient = caller?.role === 'family' && target.role === 'patient' &&
    (caller.linkedPatientIds || []).includes(document.id) && !!caller.caregiverId &&
    target.caregiverId === caller.caregiverId;
  if (document.id !== callerUid && !managedBy(callerUid, caller, target) && !unassigned && !familyPatient) return {profile: null};
  if (unassigned) {
    // Linking an existing account only needs identity, not clinical details.
    return {profile: {uid: document.id, name: target.name, email: target.email, role: target.role, createdAt: target.createdAt}};
  }
  return {profile: target};
});

exports._test = {uidValue, normalizeEmail, emailValue, dateOfBirthValue, editableValues, managedBy, samePatientLinks};

