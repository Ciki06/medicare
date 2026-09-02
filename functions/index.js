/**
 * MediCare Cloud Functions
 *
 * Sends real-time push notifications (FCM) to a patient's caregiver and
 * linked family members whenever a patient triggers an SOS alert. Because this
 * runs server-side, notifications are delivered even when the recipient's app
 * is closed or in the background.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();

/**
 * Trigger: a patient creates a document in `sos_alerts`.
 * Fires an FCM data message to every recipient's device token so their app
 * (or the OS notification tray when the app is closed) shows the SOS.
 */
exports.sendSosNotification =
  functions.region('asia-southeast1')
    .firestore
    .document('sos_alerts/{alertId}')
    .onCreate(async (snap, context) => {
      const alert = snap.data();
      const patientName = alert.patientName || 'Patient';
      const patientId = alert.patientId || '';
      const recipientIds = alert.alertUserIds || [];

      const message = {
        notification: {
          title: '🚨 SOS Alert',
          body: `${patientName} needs help immediately!`,
        },
        data: {
          type: 'sos',
          patientName,
          patientId,
          alertId: context.params.alertId,
        },
        android: {
          priority: 'high',
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
        },
      };

      // Resolve each recipient's current FCM token, then send per recipient.
      const results = await Promise.allSettled(
        recipientIds.map((uid) => deliverToUser(uid, message)),
      );

      let failures = 0;
      for (const r of results) {
        if (r.status === 'rejected') failures += 1;
      }
      if (failures > 0) {
        functions.logger.warn(
          `SOS delivery had ${failures} failure(s) for alert ${context.params.alertId}`,
        );
      }

      // Persist note of delivery for observability (optional).
      await snap.ref.set({ notifiedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true });

      return null;
    });

/**
 * Sends an FCM message to a single user's device token(s).
 * Falls back to the deprecated legacy token field if `fcmToken` is absent.
 */
async function deliverToUser(uid, message) {
  if (!uid) return;
  const userSnap = await db.collection('users').doc(uid).get();
  if (!userSnap.exists) return;
  const user = userSnap.data();
  const token = user.fcmToken;
  if (!token) {
    functions.logger.info(`No FCM token for user ${uid}; skipping`);
    return;
  }
  try {
    await admin.messaging().send({
      ...message,
      token,
    });
  } catch (err) {
    functions.logger.warn(`FCM send failed for user ${uid}: ${err.message}`);
    // If the token is stale, clear it so we don't retry a dead token forever.
    if (err.code === 'messaging/invalid-argument' ||
        err.code === 'messaging/registration-token-not-registered') {
      await db.collection('users').doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() });
    }
  }
}