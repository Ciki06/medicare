const test = require('node:test');
const assert = require('node:assert/strict');
require('../index');
const {active, validSdp, iceServers} = require('../calls')._test;
test('call leases reject expired and terminal sessions', () => {
  assert.equal(active({state: 'ringing', expiresAt: 101}, 100), true);
  assert.equal(active({state: 'accepted', expiresAt: 100}, 100), false);
  assert.equal(active({state: 'ended', expiresAt: 200}, 100), false);
});
test('signaling descriptions are typed and bounded', () => {
  assert.ok(validSdp({type: 'offer', sdp: 'v=0\r\n'}, 'offer'));
  assert.ok(!validSdp({type: 'answer', sdp: 'v=0'}, 'offer'));
  assert.ok(!validSdp({type: 'offer', sdp: 'v=0' + 'x'.repeat(100000)}, 'offer'));
  assert.ok(Array.isArray(iceServers('test')));
});
test('call lifecycle enforces roles, busy state, accept once, and end', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const admin = require('firebase-admin');
  const ft = require('firebase-functions-test')({projectId: 'demo-medicare'});
  const call = ft.wrap(require('../calls').voiceCall);
  const db = admin.firestore();
  const ctx = uid => ({auth: {uid}});
  await db.doc('chats/call-test').set({participants: ['call-a', 'call-b']});
  await db.doc('call_sessions/call-a').delete(); await db.doc('call_sessions/call-b').delete();
  await assert.rejects(call({action: 'start', chatId: 'call-test'}, ctx('stranger')));
  const {callId} = await call({action: 'start', chatId: 'call-test'}, ctx('call-a'));
  await assert.rejects(call({action: 'start', chatId: 'call-test'}, ctx('call-b')), /already in a call/);
  await assert.rejects(call({action: 'offer', callId, offer: {type: 'offer', sdp: 'v=0'}}, ctx('call-b')));
  await call({action: 'offer', callId, offer: {type: 'offer', sdp: 'v=0'}}, ctx('call-a'));
  await assert.rejects(call({action: 'accept', callId, answer: {type: 'answer', sdp: 'v=0'}}, ctx('call-a')));
  await call({action: 'accept', callId, answer: {type: 'answer', sdp: 'v=0'}}, ctx('call-b'));
  await assert.rejects(call({action: 'accept', callId, answer: {type: 'answer', sdp: 'v=0'}}, ctx('call-b')));
  await call({action: 'end', callId}, ctx('call-a'));
  assert.equal((await db.doc(`calls/${callId}`).get()).data().state, 'ended');
  assert.ok((await db.doc('call_sessions/call-b').get()).data().expiresAt <= Date.now());
  ft.cleanup();
});
