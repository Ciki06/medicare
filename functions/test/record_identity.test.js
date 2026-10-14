'use strict';
const test=require('node:test'), assert=require('node:assert/strict');
const HELPERS=['record_id_counters','record_id_maps','record_id_reservations','record_schema','medication_keys','appointment_keys'];
async function noHelpers(db){for(const entity of HELPERS)assert.equal((await db.collection(entity).get()).size,0,entity);}
test('counter-free allocation and concurrent profile creation preserve existing IDs', {skip:!process.env.FIRESTORE_EMULATOR_HOST}, async()=>{
 const admin=require('firebase-admin');require('../index');
 const {reserveRecordIds,saveAccountProfile}=require('../record_identity');
 const db=admin.firestore();
 await db.doc('users/allocator-care').set({role:'caregiver',uid:'allocator-care',id:900});
 const blocks=await Promise.all(Array.from({length:8},()=>reserveRecordIds.run({entity:'medications',count:16},{auth:{uid:'allocator-care'}})));
 assert.equal(new Set(blocks.flatMap(b=>Array.from({length:16},(_,i)=>b.start+i))).size,128);
 assert.ok(blocks.every(block=>Number.isSafeInteger(block.start)&&Number.isSafeInteger(block.end)));
 await assert.rejects(reserveRecordIds.run({entity:'moods',count:16},{auth:{uid:'allocator-care'}}),error=>error.code==='permission-denied');
 await assert.rejects(reserveRecordIds.run({entity:'medications',count:0},{auth:{uid:'allocator-care'}}),error=>error.code==='invalid-argument');
 const auth=admin.auth(), original=auth.getUser;
 auth.getUser=async uid=>({uid,email:'test@example.invalid'});
 try{
  const input={uid:'allocator-patient',role:'patient',caregiverId:'allocator-care',name:'Patient'};
  const values=await Promise.all([saveAccountProfile.run(input,{auth:{uid:'allocator-care'}}),saveAccountProfile.run(input,{auth:{uid:'allocator-care'}})]);
  assert.equal(values[0].id,values[1].id);assert.ok(Number.isSafeInteger(values[0].id));
  assert.equal(values[0].caregiverId,900);assert.equal(values[0].caregiver_uid,'allocator-care');
  assert.deepEqual(await saveAccountProfile.run({...input,name:'Changed'},{auth:{uid:'allocator-care'}}),values[0]);
  await assert.rejects(saveAccountProfile.run({...input,role:'family'},{auth:{uid:'allocator-care'}}),error=>error.code==='already-exists');
  await noHelpers(db);
 }finally{auth.getUser=original;await db.doc('users/allocator-patient').delete();await db.doc('users/allocator-care').delete();}
});

test('deleted medication references and scoped lookups work without metadata collections', {skip:!process.env.FIRESTORE_EMULATOR_HOST}, async()=>{
 const admin=require('firebase-admin');require('../index');
 const {retainMedicationIdentity,getRecordIdentities}=require('../record_identity');
 const db=admin.firestore(), snapshot=(exists,data)=>({exists,data:()=>data});
 const data={id:901,uid:'901',legacy_uid:'deleted-schedule',patient_uid:'identity-patient'};
 const patient={role:'patient',id:801,name:'Unchanged',medicalHistory:['Unchanged'],caregiver_uid:'identity-care'};
 await db.doc('users/identity-patient').set(patient);
 await db.doc('users/identity-outsider').set({role:'patient',id:802});
 await db.doc('medications/901').set(data);
 await db.doc('medications/902').set({id:902,legacy_uid:'private-schedule',patient_uid:'identity-outsider'});
 await db.doc('medication_actions/901').set({id:901,legacy_uid:'legacy-action',patient_uid:'identity-patient',medicationId:901,legacy_medication_uid:'deleted-schedule'});
 const creation={before:snapshot(false),after:snapshot(true,data)};
 await retainMedicationIdentity.run(creation,{params:{id:'901'}});
 await db.doc('medications/901').delete();
 const deletion={before:snapshot(true,data),after:snapshot(false)};
 await retainMedicationIdentity.run(deletion,{params:{id:'901'}});
 await retainMedicationIdentity.run(deletion,{params:{id:'901'}});
 await retainMedicationIdentity.run(creation,{params:{id:'901'}});
 assert.deepEqual((await db.doc('users/identity-patient').get()).data(),{...patient,retiredMedicationIds:[901]});
 const {mappings}=await getRecordIdentities.run(null,{auth:{uid:'identity-patient'}});
 assert.equal(mappings.medications['deleted-schedule'],901);
 assert.equal(mappings.medication_actions['legacy-action'],901);
 assert.equal(mappings.medications['private-schedule'],undefined);
 assert.equal(mappings.medications['901'],undefined);
 await assert.rejects(getRecordIdentities.run(null,{}),error=>error.code==='unauthenticated');
 await noHelpers(db);
 await Promise.all(['users/identity-patient','users/identity-outsider','medications/902','medication_actions/901'].map(key=>db.doc(key).delete()));
});
