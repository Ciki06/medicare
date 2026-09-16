const test = require('node:test');
const assert = require('node:assert/strict');

const {fcmTokensForUser, chunks, stringValue} = require('../index')._test;
const {sosLocationText} = require('../index')._test;

test('collects every unique valid FCM token for a contact', () => {
  const first = 'a'.repeat(30);
  const second = 'b'.repeat(30);
  assert.deepEqual(
    fcmTokensForUser({
      fcmTokens: [first, second, first, '', 42],
      fcmToken: second,
    }),
    [first, second],
  );
});

test('splits multicast recipients at the FCM limit', () => {
  const values = Array.from({length: 1001}, (_, index) => `${index}`);
  assert.deepEqual(chunks(values, 500).map((part) => part.length), [500, 500, 1]);
});

test('normalizes only string values', () => {
  assert.equal(stringValue('  patient  '), 'patient');
  assert.equal(stringValue(null), '');
});

test('SOS location never fabricates a map link for missing or invalid coordinates', () => {
  for (const alert of [{}, {locationStatus: 'pending'}, {locationStatus: 'permission_denied'},
    {locationStatus: 'available', latitude: 95, longitude: 20},
    {locationStatus: 'available', latitude: '1.2', longitude: 20}]) {
    assert.ok(!sosLocationText(alert).includes('https://'));
  }
  assert.match(sosLocationText({locationStatus: 'available', latitude: 0, longitude: 0,
    locationAccuracy: 4, locationCapturedAt: 0, locationName: 'Nursing Home Main Building'}), /Nursing Home Main Building/);
});

test('SOS chat entry does not trigger a second push notification', async () => {
  const functionsTest = require('firebase-functions-test')();
  const wrapped = functionsTest.wrap(require('../index').sendChatNotification);
  assert.equal(await wrapped({data: () => ({type: 'sos_location'})}, {params: {chatId: 'chat', messageId: 'sos-a'}}), null);
  functionsTest.cleanup();
});

test('SOS chat fanout is idempotent and late location updates preserve newer chat previews', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const admin = require('firebase-admin');
  const functionsTest = require('firebase-functions-test')({projectId: 'demo-medicare'});
  const wrapped = functionsTest.wrap(require('../index').syncSosLocationToChats);
  const db = admin.firestore();
  const alertRef = db.collection('sos_alerts').doc('fanout-test');
  const pending = {patientId: 'fanout-p', patientName: 'Sample', alertUserIds: ['fanout-c', 'fanout-f'],
    locationStatus: 'pending', createdAt: 100};
  await alertRef.set(pending);
  const before = {exists: false, data: () => undefined};
  const after = await alertRef.get();
  await wrapped({before, after}, {params: {alertId: 'fanout-test'}});
  await wrapped({before, after}, {params: {alertId: 'fanout-test'}});
  const caregiverRoom = db.collection('chats').doc('fanout-c_fanout-p');
  const familyRoom = db.collection('chats').doc('fanout-f_fanout-p');
  assert.equal((await caregiverRoom.collection('messages').get()).size, 1);
  assert.equal((await familyRoom.collection('messages').get()).size, 1);
  assert.equal((await caregiverRoom.get()).data().unreadCount['fanout-c'], 1);
  await caregiverRoom.update({lastMessage: 'I am on my way', lastMessageAt: 200});
  await alertRef.update({locationStatus: 'available', latitude: 1.3, longitude: 103.8});
  const located = await alertRef.get();
  await wrapped({before: after, after: located}, {params: {alertId: 'fanout-test'}});
  // An out-of-order replay must retain the latest coordinates from the document.
  await wrapped({before, after}, {params: {alertId: 'fanout-test'}});
  assert.match((await caregiverRoom.collection('messages').doc('sos_fanout-test').get()).data().mapUrl, /q=1.3,103.8/);
  assert.equal((await caregiverRoom.get()).data().lastMessage, 'I am on my way');
  functionsTest.cleanup();
});

test('SOS dispatch includes caregiver and linked family with one alarm payload per token', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const admin = require('firebase-admin');
  const ft = require('firebase-functions-test')({projectId:'demo-medicare'});
  const wrapped = ft.wrap(require('../index').sendSosNotification);
  const db = admin.firestore();
  await db.doc('users/dispatch-p').set({role:'patient', caregiverId:'dispatch-c', name:'Patient'});
  await db.doc('users/dispatch-c').set({role:'caregiver', fcmTokens:['c'.repeat(30)]});
  await db.doc('users/dispatch-f').set({role:'family', linkedPatientIds:['dispatch-p'], fcmTokens:['f'.repeat(30)]});
  const ref = db.doc('sos_alerts/dispatch-test');
  await ref.set({patientId:'dispatch-p',status:'active',createdAt:Date.now()});
  const messaging = admin.messaging();
  const original = messaging.sendEachForMulticast;
  const sent = [];
  messaging.sendEachForMulticast = async message => {
    sent.push(message);
    return {successCount:message.tokens.length,failureCount:0,responses:message.tokens.map(() => ({success:true}))};
  };
  try {
    await wrapped(await ref.get(), {params:{alertId:'dispatch-test'}});
    assert.deepEqual(new Set(sent.flatMap(m => m.tokens)), new Set(['c'.repeat(30),'f'.repeat(30)]));
    for (const m of sent) {
      assert.equal(m.data.type,'sos');
      assert.equal(m.android.priority,'high');
      assert.equal(m.android.ttl, 300000);
      assert.ok(Number(m.apns.headers['apns-expiration']) > Date.now() / 1000);
      assert.equal(m.notification,undefined);
      assert.equal(m.apns.payload.aps.sound,'sos_alarm.wav');
    }
    const count = sent.length;
    await wrapped(await ref.get(), {params:{alertId:'dispatch-test'}});
    assert.equal(sent.length,count);
    const stopped = db.doc('sos_alerts/stopped-before-dispatch');
    await stopped.set({patientId:'dispatch-p',status:'active',createdAt:Date.now()});
    const oldEvent = await stopped.get();
    await stopped.update({status:'stopped'});
    await wrapped(oldEvent, {params:{alertId:'stopped-before-dispatch'}});
    assert.equal(sent.length,count);
  } finally { messaging.sendEachForMulticast = original; ft.cleanup(); }
});
