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

    // Important: this is delivered as a DATA-ONLY message on Android (no
    // top-level `notification`). Firebase Messaging wakes the killed app and
    // runs `onBackgroundMessage`, which shows the full-screen alarm (custom
    // SOS sound + fullScreenIntent + red). On iOS the `aps.alert` below is
    // rendered natively by APNs even when the app is terminated.
    const baseMessage = {
      data: {
        type: 'sos',
        patientName,
        patientId,
        alertId: context.params.alertId,
        deepLink: `medicare://sos/alert?alertId=${context.params.alertId}`,
      },
      android: {
        priority: 'high',
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            alert: {
              title: `🚨 SOS from ${patientName}`,
              body: `${patientName} needs help immediately!`,
            },
            // Custom sound file bundled in the iOS app as Runner/sos_alarm.wav.
            sound: 'sos_alarm.wav',
            badge: 1,
            'interruption-level': 'time-sensitive',
            'relevance-score': 1.0,
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

/**
 * A chat message is created -> send a push notification to every other
 * participant (the recipients) so they get notified even while the app is
 * closed. Uses the standard `notification` payload, which the OS renders in
 * the tray automatically for backgrounded / killed apps (the SOS emergency
 * path is intentionally data-only so it can run the custom full-screen alarm;
 * chat does not need that).
 */
exports.sendChatNotification = functions
  .region('asia-southeast1')
  .firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const senderId = stringValue(message.senderId);
    const senderName = stringValue(message.senderName);
    const text = stringValue(message.text);
    if (!senderId || !text) {
      functions.logger.warn('Chat message missing sender or text', {
        chatId: context.params.chatId,
        messageId: context.params.messageId,
      });
      return null;
    }

    const chatRoomSnapshot = await db
      .collection('chats')
      .doc(context.params.chatId)
      .get();
    if (!chatRoomSnapshot.exists) {
      functions.logger.warn('Chat room for message was not found', {
        chatId: context.params.chatId,
        messageId: context.params.messageId,
      });
      return null;
    }

    const participants = Array.isArray(chatRoomSnapshot.data().participants)
      ? chatRoomSnapshot.data().participants.filter((uid) => typeof uid === 'string')
      : [];
    const recipients = participants.filter((uid) => uid !== senderId);
    if (recipients.length === 0) return null;

    const recipientSnapshots = await db.getAll(
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

    const preview = text.length > 200 ? `${text.slice(0, 200)}…` : text;
    const baseMessage = {
      data: {
        type: 'chat',
        chatId: context.params.chatId,
        senderId,
        senderName,
        text: preview,
        deepLink: `medicare://chat/${context.params.chatId}?senderId=${senderId}`,
      },
      notification: {
        title: senderName || 'New message',
        body: preview,
      },
      android: {
        priority: 'high',
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
          functions.logger.error('Chat multicast request failed', {
            chatId: context.params.chatId,
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

    functions.logger.info('Chat notification dispatch complete', {
      chatId: context.params.chatId,
      messageId: context.params.messageId,
      senderId,
      recipientCount: recipients.length,
      attemptedDeviceCount,
      successCount,
      failureCount,
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
