const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, getDoc} = require('firebase/firestore');
const {ref, uploadBytes} = require('firebase/storage');

test('chat media, self-owned presence, and SOS location enforce access rules', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
}, async () => {
  const environment = await initializeTestEnvironment({projectId: 'demo-medicare',
    firestore: {rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8')},
    storage: {rules: fs.readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8')}});
  try {
    await environment.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, 'users/patient'), {role: 'patient', caregiverId: 'caregiver'});
      await setDoc(doc(db, 'chats/caregiver_patient'), {participants: ['patient', 'caregiver'],
        lastMessage: '', lastMessageAt: 0, lastMessageSender: '', unreadCount: {patient: 0, caregiver: 0}});
    });
    const patient = environment.authenticatedContext('patient');
    const caregiver = environment.authenticatedContext('caregiver');
    const stranger = environment.authenticatedContext('stranger');
    const presence = 'chats/caregiver_patient/presence/patient';
    await assertSucceeds(setDoc(doc(patient.firestore(), presence), {readThrough: 100, typingAt: 0}));
    await assertFails(updateDoc(doc(caregiver.firestore(), presence), {readThrough: 200}));
    await assertFails(getDoc(doc(stranger.firestore(), presence)));
    const message = {senderId: 'patient', senderName: 'Patient', text: 'Image', type: 'image', mediaUrl: 'https://example.invalid/image', createdAt: 100};
    await assertSucceeds(setDoc(doc(patient.firestore(), 'chats/caregiver_patient/messages/image'), message));
    await assertFails(setDoc(doc(patient.firestore(), 'chats/caregiver_patient/messages/spoof'), {...message, type: 'sos_location'}));
    const alert = {patientId: 'patient', patientName: 'Patient', caregiverId: 'caregiver', alertUserIds: [], status: 'active', createdAt: 1, triggerSource: 'in_app', locationStatus: 'pending'};
    await assertSucceeds(setDoc(doc(patient.firestore(), 'sos_alerts/alert'), alert));
    const legacyAlert = {...alert};
    delete legacyAlert.locationStatus;
    await assertSucceeds(setDoc(doc(patient.firestore(), 'sos_alerts/legacy'), legacyAlert));
    await assertSucceeds(updateDoc(doc(patient.firestore(), 'sos_alerts/alert'), {locationStatus: 'available', latitude: 0, longitude: 0, locationAccuracy: 5, locationCapturedAt: 100}));
    await assertFails(updateDoc(doc(patient.firestore(), 'sos_alerts/alert'), {latitude: 91}));
    await assertFails(updateDoc(doc(patient.firestore(), 'sos_alerts/alert'), {alertUserIds: ['stranger']}));
    await assertFails(updateDoc(doc(stranger.firestore(), 'sos_alerts/alert'), {latitude: 1}));
    const file = 'chat_media/caregiver_patient/patient/sample.image';
    await assertSucceeds(uploadBytes(ref(patient.storage(), file), new Uint8Array([1, 2]), {contentType: 'image/jpeg'}));
    await assertFails(uploadBytes(ref(stranger.storage(), 'chat_media/caregiver_patient/stranger/sample.image'), new Uint8Array([1]), {contentType: 'image/jpeg'}));
    await assertFails(uploadBytes(ref(patient.storage(), 'chat_media/caregiver_patient/patient/not-image'), new Uint8Array([1]), {contentType: 'text/html'}));
  } finally { await environment.cleanup(); }
});
