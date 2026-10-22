'use strict';

const {createHash} = require('node:crypto');
const functions = require('firebase-functions');
const admin = require('firebase-admin');

const TERMINAL_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
function managedUid(callerUid, requestId) {
  if (typeof callerUid !== 'string' || !callerUid || typeof requestId !== 'string' || !/^[a-f0-9]{32}$/.test(requestId)) {
    throw new functions.https.HttpsError('invalid-argument', 'A valid account creation request ID is required.');
  }
  return 'managed_' + createHash('sha256').update(callerUid).update('\0').update(requestId).digest('hex');
}
const normalizedEmail = value => typeof value === 'string' ? value.trim().toLowerCase() : '';
function errorCode(error) {
  const code = String(error?.code || 'unknown');
  return /^[a-z0-9_/-]{1,80}$/i.test(code) ? code : 'unknown';
}
function assertOperation(operation, expected) {
  if (operation && (operation.uid !== expected.uid || operation.caregiverId !== expected.caregiverId ||
      operation.email !== expected.email || operation.role !== expected.role)) {
    throw new functions.https.HttpsError('already-exists', 'This creation request was already used for a different account.');
  }
}
function assertProfile(profile, expected) {
  if (profile && (profile.uid !== expected.uid || profile.caregiverId !== expected.caregiverId || profile.role !== expected.role)) {
    throw new functions.https.HttpsError('permission-denied', 'This account does not match the requested care relationship.');
  }
}
function assertAuth(account, expected) {
  if (account.uid !== expected.uid || normalizedEmail(account.email) !== expected.email || account.disabled) {
    throw new functions.https.HttpsError('already-exists', 'This creation request does not match the existing account.');
  }
}
function publicError(error) {
  if (error instanceof functions.https.HttpsError) return error;
  if (error.code === 'auth/email-already-exists' || error.code === 'auth/uid-already-exists') {
    return new functions.https.HttpsError('already-exists', 'That email is already used by another account.');
  }
  if (error.code === 'auth/invalid-password' || error.code === 'auth/invalid-email') {
    return new functions.https.HttpsError('invalid-argument', 'Check the account email and password.');
  }
  if (error.code === 10 || error.code === 'aborted') return new functions.https.HttpsError('aborted', 'Account creation was interrupted. Retry the same request.');
  return new functions.https.HttpsError('unavailable', 'Account creation could not finish. Retry the same request.');
}

/**
 * Auth and Firestore cannot commit atomically. A durable operation makes an
 * interrupted Auth creation recoverable without deleting an account a replay
 * may already be using. It never stores a password, token or request ID.
 * Only completed operations expire; unfinished work remains available to retry.
 */
function createManagedProvisioner({db, auth, now = Date.now}) {
  return async ({callerUid, requestId, email, password, role, values}) => {
    const uid = managedUid(callerUid, requestId);
    const expected = {uid,caregiverId:callerUid,email,role};
    const operationRef = db.doc('_account_provisioning/' + uid);
    const profileRef = db.doc('users/' + uid);
    const stamp = () => new Date(now()).toISOString();
    try {
      const previousProfile = await db.runTransaction(async transaction => {
        const [operationSnap,profileSnap] = await Promise.all([transaction.get(operationRef),transaction.get(profileRef)]);
        const operation = operationSnap.data(), profile = profileSnap.data();
        assertOperation(operation,expected);
        assertProfile(profile,expected);
        if (operation?.status === 'complete' && !profile) {
          throw new functions.https.HttpsError('failed-precondition', 'The completed account profile is missing. Ask the caregiver to review this account.');
        }
        if (!operation) {
          transaction.create(operationRef,{...expected,status:'pending',createdAt:stamp(),updatedAt:stamp()});
        }
        return profile || null;
      });

      let account;
      if (previousProfile) {
        // An existing profile must not cause a deleted Auth account to be
        // recreated with a password from an old request.
        account = await auth.getUser(uid);
      } else {
        try {
          account = await auth.createUser({uid,email,password,displayName:values.name});
        } catch (error) {
          // Either unique constraint may be reported when both UID and email
          // already exist. Only this deterministic UID may ever be reused.
          if (!['auth/uid-already-exists','auth/email-already-exists'].includes(error.code)) throw error;
          try { account = await auth.getUser(uid); }
          catch (lookupError) {
            if (lookupError.code === 'auth/user-not-found') throw error;
            throw lookupError;
          }
        }
      }
      assertAuth(account,expected);

      return await db.runTransaction(async transaction => {
        const [operationSnap,profileSnap] = await Promise.all([transaction.get(operationRef),transaction.get(profileRef)]);
        const operation = operationSnap.data(), existing = profileSnap.data();
        assertOperation(operation,expected);
        assertProfile(existing,expected);
        if (!operation) throw new functions.https.HttpsError('aborted', 'The account operation changed. Retry the same request.');
        if (operation.status === 'complete') {
          if (!existing) throw new functions.https.HttpsError('failed-precondition', 'The completed account profile is missing. Ask the caregiver to review this account.');
          return {profile:existing};
        }
        const timestamp = stamp();
        const profile = existing || {uid,role,email,createdAt:timestamp,updatedAt:timestamp,
          ...Object.fromEntries(Object.entries(values).filter(([,value]) => value !== null))};
        if (!existing) transaction.create(profileRef,profile);
        // The profile and completion marker are one Firestore commit. A late
        // failure from another invocation cannot downgrade a completed request.
        transaction.set(operationRef,{...expected,status:'complete',createdAt:operation.createdAt,
          updatedAt:timestamp,deleteAfter:admin.firestore.Timestamp.fromMillis(now()+TERMINAL_RETENTION_MS)});
        return {profile};
      });
    } catch (error) {
      try {
        await db.runTransaction(async transaction => {
          const snapshot = await transaction.get(operationRef);
          const operation = snapshot.data();
          if (!operation || operation.status === 'complete') return;
          assertOperation(operation,expected);
          transaction.update(operationRef,{status:'retry',updatedAt:stamp(),lastErrorCode:errorCode(error),
            deleteAfter:admin.firestore.FieldValue.delete()});
        });
      } catch (recordError) {
        functions.logger.error('Managed account operation needs a retry', {uid,code:errorCode(recordError)});
      }
      // Do not delete Auth here: a timeout does not prove that a request failed,
      // and another invocation may already have committed the shared profile.
      throw publicError(error);
    }
  };
}

module.exports = {createManagedProvisioner,managedUid,errorCode,TERMINAL_RETENTION_MS};

