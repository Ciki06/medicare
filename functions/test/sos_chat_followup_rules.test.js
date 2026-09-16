const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, getDoc, writeBatch, serverTimestamp} = require('firebase/firestore');

test('SOS reply and acknowledgement are atomic; stopped alerts and chat metadata stay protected', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId:'demo-medicare',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      const db=ctx.firestore();
      await setDoc(doc(db,'users/follow-p'), {role:'patient',caregiverId:'follow-c'});
      await setDoc(doc(db,'users/follow-c'), {role:'caregiver'});
      await setDoc(doc(db,'chats/follow-room'), {participants:['follow-p','follow-c']});
      for (const id of ['reply','stop']) await setDoc(doc(db,`sos_alerts/follow-${id}`), {patientId:'follow-p',patientName:'Patient',caregiverId:'follow-c',alertUserIds:['follow-c'],status:'active',createdAt:Date.now()});
    });
    const c=env.authenticatedContext('follow-c').firestore();
    const p=env.authenticatedContext('follow-p').firestore();
    const outsider=env.authenticatedContext('follow-other').firestore();
    const reply={senderId:'follow-c',senderName:'Carer',senderRole:'caregiver',message:"I'm on the way",createdAt:serverTimestamp()};
    const batch=writeBatch(c);
    batch.set(doc(c,'sos_alerts/follow-reply/responses/response'),reply);
    batch.update(doc(c,'sos_alerts/follow-reply'),{status:'acknowledged',acknowledgedBy:'follow-c'});
    await assertSucceeds(batch.commit());
    await assertSucceeds(getDoc(doc(p,'sos_alerts/follow-reply/responses/response')));
    await assertFails(getDoc(doc(outsider,'sos_alerts/follow-reply')));
    await assertFails(setDoc(doc(c,'sos_alerts/follow-reply/responses/late'),reply));
    await assertSucceeds(updateDoc(doc(p,'sos_alerts/follow-stop'),{status:'stopped'}));
    await assertFails(updateDoc(doc(c,'sos_alerts/follow-stop'),{status:'active'}));
    const image={senderId:'follow-c',senderName:'Carer',text:'',type:'image',mediaUrl:'https://example.invalid/image',caption:'',createdAt:Date.now(),forwarded:true};
    await assertSucceeds(setDoc(doc(c,'chats/follow-room/messages/image'),image));
    await assertSucceeds(setDoc(doc(c,'chats/follow-room/messages/voice'),{...image,type:'voice',durationSeconds:12}));
    await assertFails(setDoc(doc(c,'chats/follow-room/messages/invalid'),{...image,type:'voice',durationSeconds:-5}));
    await assertFails(setDoc(doc(c,'chats/follow-room/messages/empty'),{...image,type:'text'}));
    await assertFails(setDoc(doc(outsider,'chats/follow-room/messages/spoof'),image));
  } finally { await env.cleanup(); }
});
