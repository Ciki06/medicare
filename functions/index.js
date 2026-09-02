/**
 * MediCare Cloud Functions
 *
 * A patient creates a minimal SOS event. This trusted backend resolves the
 * current caregiver and every linked family member, records those recipients
 * on the alert, and sends an FCM notification to all of their registered
 * Android/iOS device tokens.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const INVALID_TOKEN_CODES = new Set([
  'messaging/invalid-argument',
  'messaging/registration-token-not-registered',
]);

exports.sendSosNotification = functions
  .region('asia-southeast1')
  .firestore
  .document('sos_alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    const patientId = stringValue(alert.patientId);
    if (!patientId) {
      functions.logger.error('SOS alert has no patientId', {
        alertId: context.params.alertId,
      });
      await snap.ref.set({dispatchStatus: 'invalid'}, {merge: true});
      return null;
    }

    const patientSnapshot = await db.collection('users').doc(patientId).get();
    if (!patientSnapshot.exists) {
      functions.logger.error('SOS patient profile was not found', {
        alertId: context.params.alertId,
        patientId,
      });
      await snap.ref.set({dispatchStatus: 'patient_not_found'}, {merge: true});
      return null;
    }

    const patient = patientSnapshot.data();
    if (stringValue(patient.role).toLowerCase() !== 'patient') {
      functions.logger.error('Non-patient account attempted to create SOS', {
        alertId: context.params.alertId,
        patientId,
      });
      await snap.ref.set({dispatchStatus: 'invalid_patient_role'}, {merge: true});
      return null;
    }

    const patientName = stringValue(patient.name) || 'A patient';
    const caregiverId = stringValue(patient.caregiverId);
    const [familySnapshot, legacyFamilySnapshot] = await Promise.all([
      db.collection('users')
        .where('linkedPatientIds', 'array-contains', patientId)
        .get(),
      db.collection('users')
        .where('linkedPatientId', '==', patientId)
        .get(),
    ]);

    const recipientIds = new Set();
    if (caregiverId) recipientIds.add(caregiverId);
    const familyDocuments = new Map();
    for (const familyDocument of [
      ...familySnapshot.docs,
      ...legacyFamilySnapshot.docs,
    ]) {
      familyDocuments.set(familyDocument.id, familyDocument);
    }
    for (const familyDocument of familyDocuments.values()) {
      const family = familyDocument.data();
      if (stringValue(family.role).toLowerCase() === 'family') {
        recipientIds.add(familyDocument.id);
      }
    }
    recipientIds.delete(patientId);

    const recipients = [...recipientIds];
    const recipientSnapshots = recipients.length === 0
      ? []
      : await db.getAll(
        ...recipients.map((uid) => db.collection('users').doc(uid)),
      );

    const tokensByUser = new Map();
    const seenTokens = new Set();
    for (const recipientSnapshot of recipientSnapshots) {
      if (!recipientSnapshot.exists) continue;
      const tokens = fcmTokensForUser(recipientSnapshot.data())
        .filter((token) => {
          if (seenTokens.has(token)) return false;
          seenTokens.add(token);
          return true;
        });
      if (tokens.length > 0) tokensByUser.set(recipientSnapshot.id, tokens);
    }

    await snap.ref.set({
      patientName,
      caregiverId,
      alertUserIds: recipients,
      recipientsResolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      dispatchStatus: 'sending',
    }, {merge: true});

    const baseMessage = {
      notification: {
        title: '🚨 SOS Alert',
        body: `${patientName} needs help immediately!`,
      },
      data: {
        type: 'sos',
        patientName,
        patientId,
        alertId: context.params.alertId,
        deepLink: `medicare://sos/alert?alertId=${context.params.alertId}`,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'sos_alerts',
          priority: 'max',
          defaultSound: true,
          visibility: 'public',
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
            'interruption-level': 'time-sensitive',
          },
        },
      },
    };

    let attemptedDeviceCount = 0;
    let successCount = 0;
    let failureCount = 0;
    for (const [uid, tokens] of tokensByUser.entries()) {
      for (const tokenChunk of chunks(tokens, 500)) {
        attemptedDeviceCount += tokenChunk.length;
        let response;
        try {
          response = await admin.messaging().sendEachForMulticast({
            ...baseMessage,
            tokens: tokenChunk,
          });
        } catch (error) {
          failureCount += tokenChunk.length;
          functions.logger.error('SOS multicast request failed', {
            alertId: context.params.alertId,
            uid,
            deviceCount: tokenChunk.length,
            error: error?.message || String(error),
          });
          continue;
        }
        successCount += response.successCount;
        failureCount += response.failureCount;

        const invalidTokens = [];
        response.responses.forEach((result, index) => {
          if (!result.success && INVALID_TOKEN_CODES.has(result.error?.code)) {
            invalidTokens.push(tokenChunk[index]);
          }
        });
        if (invalidTokens.length > 0) {
          await removeInvalidTokens(uid, invalidTokens);
        }
      }
    }

    const dispatchStatus = recipients.length === 0
      ? 'no_contacts'
      : attemptedDeviceCount === 0
        ? 'no_registered_devices'
        : failureCount === 0
          ? 'sent'
          : successCount > 0
            ? 'partially_sent'
            : 'failed';

    await snap.ref.set({
      dispatchStatus,
      notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      notificationRecipientCount: recipients.length,
      notificationDeviceCount: attemptedDeviceCount,
      notificationSuccessCount: successCount,
      notificationFailureCount: failureCount,
    }, {merge: true});

    functions.logger.info('SOS notification dispatch complete', {
      alertId: context.params.alertId,
      patientId,
      recipientCount: recipients.length,
      attemptedDeviceCount,
      successCount,
      failureCount,
      dispatchStatus,
    });
    return null;
  });

function fcmTokensForUser(user = {}) {
  const values = [];
  if (Array.isArray(user.fcmTokens)) values.push(...user.fcmTokens);
  values.push(user.fcmToken);
  return [...new Set(values
    .map(stringValue)
    .filter((token) => token.length > 20))];
}

async function removeInvalidTokens(uid, invalidTokens) {
  const userRef = db.collection('users').doc(uid);
  const snapshot = await userRef.get();
  if (!snapshot.exists) return;
  const data = snapshot.data();
  const updates = {
    fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
  };
  if (invalidTokens.includes(stringValue(data.fcmToken))) {
    updates.fcmToken = admin.firestore.FieldValue.delete();
  }
  await userRef.update(updates);
}

function chunks(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

function stringValue(value) {
  return typeof value === 'string' ? value.trim() : '';
}

// Pure helpers are exported for focused unit tests without initializing an
// emulator or sending real notifications.
exports._test = {fcmTokensForUser, chunks, stringValue};
