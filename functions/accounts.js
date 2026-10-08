'use strict';
/**
 * Caregiver account email changes.
 *
 * A client cannot rewrite another user's Firebase Auth email, so a caregiver
 * editing the email of a patient, family member or pharmacist calls this
 * trusted backend. The caller must own the target account or be the caregiver
 * that manages it, and must confirm their own current password so an unlocked
 * device cannot silently repoint someone's login.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const db = admin.firestore();
const region = functions.region('asia-southeast1');

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_EMAIL_LENGTH = 254;

function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function isValidEmail(email) {
  return typeof email === 'string' &&
    email.length > 0 && email.length <= MAX_EMAIL_LENGTH &&
    EMAIL_PATTERN.test(email);
}

function isSelf(callerUid, targetUid) {
  return callerUid === targetUid;
}

function canManageEmail(callerUid, callerRole, targetUid, target) {
  if (isSelf(callerUid, targetUid)) return true;
  return callerRole === 'caregiver' && !!target && target.caregiverId === callerUid;
}

// Mirrors the Firebase auth errors the caregiver can act on; anything else is
// reported as a generic failure so internals never leak to the client.
function emailChangeError(error) {
  const code = String((error && error.code) || '');
  if (code.includes('email-already-exists')) {
    return new functions.https.HttpsError('already-exists', 'That email is already used by another account.');
  }
  if (code.includes('user-not-found')) {
    return new functions.https.HttpsError('not-found', 'That account no longer exists.');
  }
  if (code.includes('invalid-email')) {
    return new functions.https.HttpsError('invalid-argument', 'Enter a valid email address.');
  }
  if (code.includes('invalid-password') || code.includes('invalid-login-credentials') ||
      code.includes('user-disabled')) {
    return new functions.https.HttpsError('invalid-argument', 'Your current password is incorrect.');
  }
  if (code.includes('token-expired') || code.includes('invalid-id-token')) {
    return new functions.https.HttpsError('unauthenticated', 'Session expired. Please sign in again.');
  }
  if (code.includes('too-many-requests')) {
    return new functions.https.HttpsError('resource-exhausted', 'Too many attempts. Please try again later.');
  }
  return new functions.https.HttpsError('internal', 'Could not update the email address.');
}

// Family members keep a denormalised copy of the patient emails they are
// linked to, so a patient's new address has to replace the old one everywhere.
async function replaceLinkedPatientEmail(patientId, previousEmail, nextEmail) {
  if (!previousEmail || previousEmail === nextEmail) return;
  const linked = await db.collection('users')
    .where('linkedPatientIds', 'array-contains', patientId)
    .get();
  const writer = db.bulkWriter();
  for (const doc of linked.docs) {
    const emails = doc.data()?.linkedPatientEmails;
    if (!Array.isArray(emails) || !emails.includes(previousEmail)) continue;
    writer.update(doc.ref, {
      linkedPatientEmails: emails.map(email => email === previousEmail ? nextEmail : email),
    });
  }
  await writer.close();
}

exports.updateManagedAccountEmail = region.https.onCall(async (data, context) => {
  const callerUid = context.auth?.uid;
  if (!callerUid) throw new functions.https.HttpsError('unauthenticated', 'Sign in to continue.');

  const targetUid = typeof data?.uid === 'string' && data.uid ? data.uid : callerUid;
  const email = normalizeEmail(data?.email);
  if (!isValidEmail(email)) {
    throw new functions.https.HttpsError('invalid-argument', 'Enter a valid email address.');
  }
  const password = typeof data?.password === 'string' ? data.password : '';
  if (!password) {
    throw new functions.https.HttpsError('invalid-argument', 'Confirm your current password.');
  }

  const [callerSnap, targetSnap] = await Promise.all([
    db.doc(`users/${callerUid}`).get(),
    db.doc(`users/${targetUid}`).get(),
  ]);
  if (!targetSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'That account no longer exists.');
  }
  const target = targetSnap.data();
  const caller = callerSnap.data() || {};
  if (!canManageEmail(callerUid, caller.role, targetUid, target)) {
    throw new functions.https.HttpsError('permission-denied', 'You can only change the email of accounts you manage.');
  }

  // Re-authenticate the caller so an unlocked device cannot repoint someone
  // else's login. verifyPassword only accepts a freshly minted ID token.
  try {
    await admin.auth().verifyPassword({
      email: caller.email || context.auth.token.email,
      password,
      idToken: context.auth.token.id_token,
    });
  } catch (e) {
    throw emailChangeError(e);
  }

  const previousEmail = normalizeEmail(target.email);
  if (previousEmail === email) return {email, changed: false};

  try {
    await admin.auth().updateUser(targetUid, {email});
  } catch (e) {
    throw emailChangeError(e);
  }

  await db.doc(`users/${targetUid}`).update({email});
  await replaceLinkedPatientEmail(targetUid, previousEmail, email);
  return {email, changed: true};
});

exports._test = {normalizeEmail, isValidEmail, isSelf, canManageEmail, emailChangeError};