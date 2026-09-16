const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDocs, collection, query, where} = require('firebase/firestore');
test('family history queries authorize explicit and legacy links without caregiverId', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-medicare', firestore: {rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/history-family'), {role:'family', linkedPatientIds:['history-p']});
      await setDoc(doc(db, 'users/history-legacy'), {role:'family', linkedPatientId:'history-p'});
      await setDoc(doc(db, 'users/history-outsider'), {role:'family', linkedPatientIds:[]});
      await setDoc(doc(db, 'users/history-p'), {role:'patient', caregiverId:'history-c'});
      for (const c of ['medications','appointments','medication_actions','moods']) await setDoc(doc(db, `${c}/history-test`), {patientId:'history-p', caregiverId:'history-c'});
      await setDoc(doc(db, 'calls/rules-call'), {callerId:'history-p', calleeId:'history-family', participants:['history-p','history-family'], state:'ringing', expiresAt:Date.now()+60000});
    });
    for (const c of ['medications','appointments','medication_actions','moods']) {
      for (const uid of ['history-family','history-legacy']) await assertSucceeds(getDocs(query(collection(env.authenticatedContext(uid).firestore(), c), where('patientId','in',['history-p']))));
      await assertFails(getDocs(query(collection(env.authenticatedContext('history-outsider').firestore(), c), where('patientId','in',['history-p']))));
    }
    const family = env.authenticatedContext('history-family').firestore();
    await assertSucceeds(getDocs(query(collection(family,'calls'),where('calleeId','==','history-family'),where('state','==','ringing'))));
    await assertFails(setDoc(doc(family,'calls/spoof'), {callerId:'history-family'}));
    await assertSucceeds(setDoc(doc(family,'calls/rules-call/candidates/valid'), {senderId:'history-family',candidate:'candidate:1',sdpMid:'0',sdpMLineIndex:0}));
    await assertFails(setDoc(doc(family,'calls/rules-call/candidates/spoof'), {senderId:'history-p',candidate:'candidate:1',sdpMid:'0',sdpMLineIndex:0}));
  } finally { await env.cleanup(); }
});
