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
    const current = await snap.ref.get();
    if (current.data()?.notifiedAt) return null;
    if (current.data()?.status !== 'active') return null;
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
        ttl: 5 * 60 * 1000,
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-collapse-id': context.params.alertId,
          'apns-expiration': String(Math.floor(Date.now() / 1000) + 300),
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
        if ((await snap.ref.get()).data()?.status !== 'active') return null;
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
    // The SOS push is the sole alarm; its chat entry must never send a second push.
    if (message.type === 'sos_location') return null;
    const senderId = stringValue(message.senderId);
    const senderName = stringValue(message.senderName);
    const text = stringValue(message.text) ||
      (message.type === 'image' ? 'Image' : message.type === 'voice' ? 'Voice message' : '');
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
        notification: {channelId: 'chat_messages'},
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
exports._test = {fcmTokensForUser, chunks, stringValue, sosLocationText};

function sosLocationText(alert) {
  const {latitude, longitude} = alert;
  const valid = alert.locationStatus === 'available' &&
    Number.isFinite(latitude) && Math.abs(latitude) <= 90 &&
    Number.isFinite(longitude) && Math.abs(longitude) <= 180;
  if (valid) {
    const accuracy = Number.isFinite(alert.locationAccuracy) ? Math.round(alert.locationAccuracy) : '?';
    const captured = Number.isFinite(alert.locationCapturedAt) ? new Date(alert.locationCapturedAt).toISOString() : 'unknown';
    return `SOS! I need help. My location: ${stringValue(alert.locationName) || 'Location shared — open map'}\nAccuracy: ±${accuracy} m. Captured: ${captured}. This is a snapshot, not live tracking.`;
  }
  return alert.locationStatus === 'pending'
    ? 'SOS! I need help. Acquiring my location…'
    : 'SOS! I need help. Current location unavailable (permission, GPS or connection). Please contact me.';
}

// GPS and recipient resolution may finish in either order. A stable message ID
// makes retries and location changes update one entry in each linked chat.
exports.syncSosLocationToChats = functions.region('asia-southeast1').firestore
  .document('sos_alerts/{alertId}').onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const alert = change.after.data();
    const previous = change.before.data() || {};
    const relevant = ['alertUserIds', 'locationStatus', 'latitude', 'longitude', 'locationAccuracy', 'locationCapturedAt', 'locationName'];
    if (change.before.exists && relevant.every((k) => JSON.stringify(alert[k]) === JSON.stringify(previous[k]))) return null;
    const recipients = [...new Set(Array.isArray(alert.alertUserIds) ? alert.alertUserIds : [])];
    const patientId = stringValue(alert.patientId);
    if (!patientId || !recipients.length) return null;
    await Promise.all(recipients.filter((id) => typeof id === 'string' && id !== patientId).map(async (uid) => {
      const room = db.collection('chats').doc([patientId, uid].sort().join('_'));
      const message = room.collection('messages').doc(`sos_${context.params.alertId}`);
      await db.runTransaction(async (transaction) => {
        // Read the latest alert inside the transaction so out-of-order triggers
        // cannot replace a captured location with an older pending state.
        const [roomSnap, messageSnap, latest] = await Promise.all([
          transaction.get(room), transaction.get(message), transaction.get(change.after.ref),
        ]);
        const data = latest.data();
        if (!data || !data.alertUserIds.includes(uid)) return;
        const text = sosLocationText(data);
        const createdAt = data.createdAt || Date.now();
        transaction.set(message, {senderId: patientId, senderName: data.patientName || 'Patient',
          text, mapUrl: data.locationStatus === 'available' ? `https://maps.google.com/?q=${data.latitude},${data.longitude}` : '', type: 'sos_location', alertId: context.params.alertId, createdAt}, {merge: true});
        if (!roomSnap.exists) {
          transaction.set(room, {participants: [patientId, uid], lastMessage: text,
            lastMessageSender: data.patientName || 'Patient', lastMessageAt: createdAt,
            unreadCount: {[patientId]: 0, [uid]: 1}});
        } else {
          const updates = {};
          if (!messageSnap.exists) updates[`unreadCount.${uid}`] = admin.firestore.FieldValue.increment(1);
          if ((roomSnap.data().lastMessageAt || 0) <= createdAt) {
            Object.assign(updates, {lastMessage: text, lastMessageAt: createdAt, lastMessageSender: data.patientName || 'Patient'});
          }
          if (Object.keys(updates).length) transaction.update(room, updates);
        }
      });
    }));
    return null;
  });

const calls = require('./calls');
exports.voiceCall = calls.voiceCall;
exports.sendIncomingCall = calls.sendIncomingCall;
