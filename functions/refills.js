'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const db = admin.firestore();
const region = functions.region('asia-southeast1');
const TRANSITIONS = Object.freeze({
  pending: ['processing', 'rejected'],
  processing: ['ready_for_pickup', 'rejected'],
  ready_for_pickup: ['collected'],
  collected: [],
  rejected: [],
});
const validKey = value => typeof value === 'string' && /^[1-9][0-9]{0,15}$/.test(value) && Number.isSafeInteger(Number(value));
function transitionAllowed(before, after) {
  return before === after || !!TRANSITIONS[before]?.includes(after);
}

exports.updateRefillRequestStatus = region.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) throw new functions.https.HttpsError('unauthenticated', 'Sign in to continue.');
  if (!validKey(data?.requestId) || !Object.hasOwn(TRANSITIONS, data?.status)) throw new functions.https.HttpsError('invalid-argument', 'Invalid refill request status.');
  const profile = (await db.doc('users/' + uid).get()).data();
  const pharmacist = profile?.role === 'pharmacist' && !!profile.caregiverId;
  const caregiver = profile?.role === 'caregiver';
  if (!pharmacist && !caregiver) throw new functions.https.HttpsError('permission-denied', 'Only the care team can update refills.');
  const reference = db.doc('refill_requests/' + data.requestId);
  return db.runTransaction(async transaction => {
    const snapshot = await transaction.get(reference);
    const request = snapshot.data();
    if (!request) throw new functions.https.HttpsError('not-found', 'Refill request was not found.');
    if (request.caregiverId !== (pharmacist ? profile.caregiverId : uid)) throw new functions.https.HttpsError('permission-denied', 'This refill belongs to another care team.');
    if (caregiver && !(data.status === 'collected' && ['ready_for_pickup', 'collected'].includes(request.status))) throw new functions.https.HttpsError('permission-denied', 'A caregiver can confirm collection once the refill is ready.');
    if (!transitionAllowed(request.status, data.status)) throw new functions.https.HttpsError('failed-precondition', 'This refill status has already changed. Refresh and try again.');
    if (request.status === data.status) return {request};
    const now = Date.now();
    let medicationRef, medication;
    if (data.status === 'collected') {
      medicationRef = db.doc('medications/' + request.medicationId);
      medication = (await transaction.get(medicationRef)).data();
      if (!medication || medication.deletedAt != null || medication.patientId !== request.patientId ||
          medication.caregiverId !== request.caregiverId) throw new functions.https.HttpsError('failed-precondition', 'The medication schedule is no longer active. Ask the caregiver to review this refill.');
      if (!Number.isSafeInteger(request.quantityRequested) || request.quantityRequested <= 0 ||
          !Number.isSafeInteger(medication.currentStock) || medication.currentStock < 0 ||
          !Number.isSafeInteger(medication.currentStock + request.quantityRequested)) throw new functions.https.HttpsError('failed-precondition', 'The refill stock values are invalid.');
    }
    const updates = {status: data.status, updatedAt: now, ...(pharmacist ? {pharmacyUid: uid} : {})};
    transaction.update(reference, updates);
    if (medicationRef) transaction.update(medicationRef, {currentStock: medication.currentStock + request.quantityRequested});
    return {request: {...request, ...updates}};
  });
});

exports._test = {TRANSITIONS, transitionAllowed, validKey};

