'use strict';

// Keep linked patient addresses consistent with the authoritative Firebase Auth
// account during profile reconciliation. Email changes are not exposed here.
const admin = require('firebase-admin');
const db = admin.firestore();

async function replaceLinkedPatientEmail(patientId, previousEmail, nextEmail) {
  if (!previousEmail || previousEmail === nextEmail) return;
  const snapshot = await db.collection('users').where('linkedPatientIds', 'array-contains', patientId).get();
  const writer = db.bulkWriter();
  for (const doc of snapshot.docs) {
    const emails = doc.data()?.linkedPatientEmails;
    if (!Array.isArray(emails) || !emails.includes(previousEmail)) continue;
    writer.update(doc.ref, {
      linkedPatientEmails: emails.map(email => email === previousEmail ? nextEmail : email),
    });
  }
  await writer.close();
}

exports._internal = {replaceLinkedPatientEmail};
