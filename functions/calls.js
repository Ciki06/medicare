'use strict';
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('node:crypto');
const {LIVE_STATES, terminalState, writeCallEvent} = require('./call_history');
const {CallMediaError, initialMedia, currentMedia, videoCapabilities, registerVideoCapability, updateMedia} = require('./call_media');
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
  if (action === 'history') {
    if (typeof data.chatId !== 'string' || !data.chatId || data.chatId.includes('/')) throw new functions.https.HttpsError('invalid-argument', 'Invalid chat.');
    const roomRef = db.doc(`chats/${data.chatId}`);
    const room = await roomRef.get();
    if (!room.data()?.participants?.includes(uid)) throw new functions.https.HttpsError('permission-denied', 'You are not in this chat.');
    // Populate events for calls made before call messages were introduced.
    // Read each current call in its transaction so opening a chat cannot
    // overwrite an in-flight status change with an older snapshot.
    let cursor;
    do {
      let query = db.collection('calls').where('chatId', '==', data.chatId).orderBy(admin.firestore.FieldPath.documentId()).limit(100);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      await Promise.all(page.docs.map(doc => db.runTransaction(async tx => {
        const [call, latestRoom] = await Promise.all([tx.get(doc.ref), tx.get(roomRef)]);
        if (!call.exists || !latestRoom.data()?.participants?.includes(uid) || !call.data().participants?.includes(uid)) return;
        writeCallEvent(tx, roomRef, latestRoom.data(), doc.id, call.data());
      })));
      cursor = page.size === 100 ? page.docs.at(-1) : null;
    } while (cursor);
    return {ok: true};
  }
  if (action === 'start') {
    if (typeof data.chatId !== 'string' || !data.chatId || data.chatId.includes('/')) throw new functions.https.HttpsError('invalid-argument', 'Invalid chat.');
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
      const record = {chatId: data.chatId, participants: ids, callerId: uid, calleeId,
        callerName: caller.data()?.name || 'Contact', calleeName: callee.data()?.name || 'Contact',
        state: 'preparing', createdAt: now, expiresAt: now + 30000,
        videoCapabilities: {[uid]: data.supportsVideo === true, [calleeId]: false},
        media: initialMedia(ids)};
      tx.set(call, record);
      writeCallEvent(tx, chat.ref, chat.data(), call.id, record, true);
      locks.forEach(ref => tx.set(ref, {callId: call.id, expiresAt: now + 30000}));
    });
    return {callId: call.id, iceServers: iceServers(uid, now)};
  }
  if (typeof data.callId !== 'string' || data.callId.includes('/')) throw new functions.https.HttpsError('invalid-argument', 'Invalid call.');
  const ref = db.doc(`calls/${data.callId}`);
  return db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    const c = snap.data();
    if (!Array.isArray(c?.participants) || !c.participants.includes(uid)) throw new functions.https.HttpsError('permission-denied', 'Not a call participant.');
    const locks = c.participants.map(id => db.doc(`call_sessions/${id}`));
    const lockSnaps = await Promise.all(locks.map(r => tx.get(r)));
    const room = await tx.get(db.doc(`chats/${c.chatId}`));
    let updates;
    if (action === 'end' || action === 'reject') {
      if (!LIVE_STATES.includes(c.state)) return {state: c.state};
      if (action === 'reject' && (uid !== c.calleeId || c.state !== 'ringing')) throw new functions.https.HttpsError('failed-precondition', 'Call is no longer ringing.');
      updates = {state: terminalState(c, action, uid, now), endedAt: now, endedBy: uid, expiresAt: now};
    } else {
      if (!active(c, now)) throw new functions.https.HttpsError('failed-precondition', 'This call has expired or ended.');
      if (action === 'offer' && uid === c.callerId && c.state === 'preparing' && validSdp(data.offer, 'offer')) {
        updates = {offer: data.offer, state: 'ringing', expiresAt: now + 45000};
      } else if (action === 'accept' && uid === c.calleeId && c.state === 'ringing' && validSdp(data.answer, 'answer')) {
        updates = {answer: data.answer, state: 'accepted', acceptedAt: now, expiresAt: now + 90000,
          videoCapabilities: {...videoCapabilities(c), [uid]: data.supportsVideo === true}};
      } else if (action === 'videoReady') {
        let capabilities;
        try {
          capabilities = registerVideoCapability(c, uid, now, room.data()?.participants);
        } catch (error) {
          if (error instanceof CallMediaError) throw new functions.https.HttpsError(error.code, error.message);
          throw error;
        }
        updates = {};
        if (c.videoCapabilities?.[uid] !== true) updates.videoCapabilities = capabilities;
        if (c.media === undefined) updates.media = currentMedia(c);
        // Repeated readiness handshakes are read-only and never affect call
        // lifetime, media revision, camera consent, locks, or chat history.
        if (Object.keys(updates).length) tx.update(ref, updates);
        return {state: c.state, videoCapabilities: capabilities, media: currentMedia(c)};
      } else if (action === 'media') {
        try {
          updates = {media: updateMedia(c, uid, data, now, room.data()?.participants)};
        } catch (error) {
          if (error instanceof CallMediaError) throw new functions.https.HttpsError(error.code, error.message);
          throw error;
        }
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
    if (updates.state && updates.state !== c.state && room.exists) {
      writeCallEvent(tx, room.ref, room.data(), ref.id, {...c, ...updates});
    }
    locks.forEach((r, i) => {
      if (updates.expiresAt !== undefined && lockSnaps[i].data()?.callId === ref.id) tx.set(r, {callId: ref.id, expiresAt: updates.expiresAt});
    });
    return {state: updates.state || c.state,
      ...(action === 'media' ? {media: updates.media, videoCapabilities: videoCapabilities(c)} : {})};
  });
});
// A killed/offline phone cannot send an end request. Finalize its shared event
// and release only locks still owned by this call.
exports.expireVoiceCalls = region.pubsub.schedule('every 1 minutes').onRun(async () => {
  const now = Date.now();
  const expired = await db.collection('calls').where('state', 'in', LIVE_STATES)
    .where('expiresAt', '<=', now).limit(200).get();
  await Promise.all(expired.docs.map(doc => db.runTransaction(async tx => {
    const latest = await tx.get(doc.ref);
    const call = latest.data();
    if (!call || !LIVE_STATES.includes(call.state) || call.expiresAt > now) return;
    const room = await tx.get(db.doc(`chats/${call.chatId}`));
    const locks = await Promise.all(call.participants.map(uid => tx.get(db.doc(`call_sessions/${uid}`))));
    const updates = {state: terminalState(call, 'expire', '', now), endedAt: call.expiresAt};
    tx.update(doc.ref, updates);
    if (room.exists) writeCallEvent(tx, room.ref, room.data(), doc.id, {...call, ...updates});
    locks.filter(lock => lock.data()?.callId === doc.id).forEach(lock => tx.delete(lock.ref));
  })));
  return null;
});
exports.sendIncomingCall = region.firestore.document('calls/{callId}').onUpdate(async change => {
  // Read current state so a retried/out-of-order trigger cannot ring a call
  // which has already been answered or ended.
  const c = (await change.after.ref.get()).data();
  if (!c) return null;
  const closing = c.state !== 'ringing' && change.before.data().state === 'ringing';
  if (!closing && (c.state !== 'ringing' || change.before.data().state === 'ringing' || c.expiresAt <= Date.now())) return null;
  const user = (await db.doc(`users/${c.calleeId}`).get()).data() || {};
  const tokens = [...new Set((user.fcmTokens || []).filter(t => typeof t === 'string' && t.length > 20))];
  for (let i = 0; i < tokens.length; i += 500) {
    if (closing) {
      await admin.messaging().sendEachForMulticast({tokens: tokens.slice(i, i + 500),
        data: {type: 'call_ended', callId: change.after.id}, android: {priority: 'high', collapseKey: change.after.id},
        apns: {headers: {'apns-push-type': 'background', 'apns-priority': '5'}, payload: {aps: {contentAvailable: true}}},
      });
      continue;
    }
    await admin.messaging().sendEachForMulticast({tokens: tokens.slice(i, i + 500),
      notification: {title: 'Incoming MediCare call', body: `${c.callerName} is calling. Open MediCare to answer.`},
      data: {type: 'call', callId: change.after.id},
      android: {priority: 'high', ttl: Math.max(0, c.expiresAt - Date.now()), collapseKey: change.after.id,
        notification: {channelId: 'voice_calls_v3', tag: change.after.id, sound: 'default'}},
      apns: {headers: {'apns-expiration': String(Math.floor(c.expiresAt / 1000)), 'apns-collapse-id': change.after.id}, payload: {aps: {sound: 'default'}}},
    });
  }
  return null;
});
exports._test = {active, validSdp, iceServers};
