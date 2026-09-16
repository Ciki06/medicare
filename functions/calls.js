'use strict';
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('node:crypto');
const db = admin.firestore();
const region = functions.region('asia-southeast1');
const active = (c, now) => c && ['preparing', 'ringing', 'accepted'].includes(c.state) && c.expiresAt > now;
function validSdp(value, type) {
  return value && value.type === type && typeof value.sdp === 'string' && value.sdp.startsWith('v=0') && value.sdp.length <= 100000;
}
function iceServers(uid, now = Date.now()) {
  const servers = [{urls: ['stun:stun.l.google.com:19302']}];
  const urls = (process.env.TURN_URLS || '').split(',').map(s => s.trim()).filter(s => /^turns?:/.test(s));
  if (urls.length && process.env.TURN_SHARED_SECRET) {
    const username = `${Math.floor(now / 1000) + 3600}:${uid}`;
    servers.push({urls, username, credential: crypto.createHmac('sha1', process.env.TURN_SHARED_SECRET).update(username).digest('base64')});
  }
  return servers;
}
exports.voiceCall = region.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) throw new functions.https.HttpsError('unauthenticated', 'Sign in to call.');
  const now = Date.now();
  const action = data?.action;
  if (action === 'start') {
    if (typeof data.chatId !== 'string' || data.chatId.includes('/')) throw new functions.https.HttpsError('invalid-argument', 'Invalid chat.');
    const call = db.collection('calls').doc();
    await db.runTransaction(async tx => {
      const chat = await tx.get(db.doc(`chats/${data.chatId}`));
      const ids = chat.data()?.participants;
      if (!Array.isArray(ids) || ids.length !== 2 || !ids.includes(uid)) throw new functions.https.HttpsError('permission-denied', 'You are not in this chat.');
      const calleeId = ids.find(id => id !== uid);
      if (!calleeId) throw new functions.https.HttpsError('invalid-argument', 'Choose another contact.');
      const locks = ids.map(id => db.doc(`call_sessions/${id}`));
      const [a, b, caller, callee] = await Promise.all([tx.get(locks[0]), tx.get(locks[1]), tx.get(db.doc(`users/${uid}`)), tx.get(db.doc(`users/${calleeId}`))]);
      if ([a, b].some(s => s.data()?.expiresAt > now)) throw new functions.https.HttpsError('already-exists', 'One of you is already in a call.');
      tx.set(call, {chatId: data.chatId, participants: ids, callerId: uid, calleeId,
        callerName: caller.data()?.name || 'Contact', calleeName: callee.data()?.name || 'Contact',
        state: 'preparing', createdAt: now, expiresAt: now + 30000});
      locks.forEach(ref => tx.set(ref, {callId: call.id, expiresAt: now + 30000}));
    });
    return {callId: call.id, iceServers: iceServers(uid, now)};
  }
  if (typeof data.callId !== 'string' || data.callId.includes('/')) throw new functions.https.HttpsError('invalid-argument', 'Invalid call.');
  const ref = db.doc(`calls/${data.callId}`);
  return db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    const c = snap.data();
    if (!c?.participants.includes(uid)) throw new functions.https.HttpsError('permission-denied', 'Not a call participant.');
    const locks = c.participants.map(id => db.doc(`call_sessions/${id}`));
    const lockSnaps = await Promise.all(locks.map(r => tx.get(r)));
    let updates;
    if (action === 'end' || action === 'reject') {
      if (action === 'reject' && (uid !== c.calleeId || c.state !== 'ringing')) throw new functions.https.HttpsError('failed-precondition', 'Call is no longer ringing.');
      if (!['preparing', 'ringing', 'accepted'].includes(c.state)) return {state: c.state};
      updates = {state: action === 'reject' ? 'rejected' : 'ended', endedAt: now, endedBy: uid, expiresAt: now};
    } else {
      if (!active(c, now)) throw new functions.https.HttpsError('failed-precondition', 'This call has expired or ended.');
      if (action === 'offer' && uid === c.callerId && c.state === 'preparing' && validSdp(data.offer, 'offer')) {
        updates = {offer: data.offer, state: 'ringing', expiresAt: now + 45000};
      } else if (action === 'accept' && uid === c.calleeId && c.state === 'ringing' && validSdp(data.answer, 'answer')) {
        updates = {answer: data.answer, state: 'accepted', acceptedAt: now, expiresAt: now + 90000};
      } else if (action === 'ice') {
        return {iceServers: iceServers(uid, now)};
      } else if (action === 'heartbeat' && c.state === 'accepted') {
        const beats = {...(c.heartbeats || {}), [uid]: now};
        // Neither peer can keep a dead peer's call busy indefinitely.
        const other = c.participants.find(id => id !== uid);
        if (now - (beats[other] || c.acceptedAt) > 90000) updates = {state: 'ended', endedAt: now, expiresAt: now};
        else updates = {heartbeats: beats, expiresAt: now + 90000};
      } else throw new functions.https.HttpsError('failed-precondition', 'Call state has changed.');
    }
    tx.update(ref, updates);
    locks.forEach((r, i) => {
      if (lockSnaps[i].data()?.callId === ref.id) tx.set(r, {callId: ref.id, expiresAt: updates.expiresAt});
    });
    return {state: updates.state || c.state};
  });
});
exports.sendIncomingCall = region.firestore.document('calls/{callId}').onUpdate(async change => {
  const c = change.after.data();
  if (c.state !== 'ringing' || change.before.data().state === 'ringing' || c.expiresAt <= Date.now()) return null;
  const user = (await db.doc(`users/${c.calleeId}`).get()).data() || {};
  const tokens = [...new Set([...(user.fcmTokens || []), user.fcmToken].filter(t => typeof t === 'string' && t.length > 20))];
  for (let i = 0; i < tokens.length; i += 500) {
    await admin.messaging().sendEachForMulticast({tokens: tokens.slice(i, i + 500),
      notification: {title: 'Incoming MediCare call', body: `${c.callerName} is calling. Open MediCare to answer.`},
      data: {type: 'call', callId: change.after.id},
      android: {priority: 'high', ttl: Math.max(0, c.expiresAt - Date.now()), collapseKey: change.after.id,
        notification: {channelId: 'voice_calls_v1', tag: change.after.id, sound: 'default'}},
      apns: {headers: {'apns-expiration': String(Math.floor(c.expiresAt / 1000)), 'apns-collapse-id': change.after.id}, payload: {aps: {sound: 'default'}}},
    });
  }
  return null;
});
exports._test = {active, validSdp, iceServers};
