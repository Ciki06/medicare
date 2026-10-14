'use strict';
const test=require('node:test'), fs=require('node:fs'), path=require('node:path');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc,collection,query,where,getDocs,runTransaction}=require('firebase/firestore');
test('canonical records require integers and matching relationships without metadata', {skip:!process.env.FIRESTORE_EMULATOR_HOST}, async()=>{
 const env=await initializeTestEnvironment({projectId:'demo-medicare-shared',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
 try{
  await env.withSecurityRulesDisabled(async context=>{
   const db=context.firestore();
   const fixtures={
    'users/patient':{role:'patient',id:7,caregiverId:2,caregiver_uid:'care',retiredMedicationIds:[11]},
    'users/care':{role:'caregiver',id:2},
    'users/family':{role:'family',id:1,caregiverId:2,caregiver_uid:'care',linkedPatientIds:[7],linkedPatientUids:['patient']},
    'appointments/1':{id:1,patientId:7,patient_uid:'patient',caregiverId:2,caregiver_uid:'care'},
   };
   for(const [key,data]of Object.entries(fixtures))await setDoc(doc(db,key),data);
  });
  const patient=env.authenticatedContext('patient').firestore(), care=env.authenticatedContext('care').firestore(), family=env.authenticatedContext('family').firestore();
  const action={id:20,uid:'20',patientId:7,patient_uid:'patient',medicationId:11,medication_uid:'11',action:'taken',timestamp:1000};
  await assertSucceeds(setDoc(doc(patient,'medication_actions/20'),action));
  await assertSucceeds(getDoc(doc(care,'medication_actions/20')));
  await assertSucceeds(getDoc(doc(family,'medication_actions/20')));
  await assertSucceeds(getDocs(query(collection(patient,'medication_actions'),where('patient_uid','==','patient'))));
  await assertSucceeds(getDocs(query(collection(care,'appointments'),where('patient_uid','==','patient'),where('caregiver_uid','==','care'))));
  await assertFails(getDocs(query(collection(care,'appointments'),where('patient_uid','==','patient'))));
  await assertFails(setDoc(doc(patient,'medication_actions/random'),{...action,id:21}));
  await assertSucceeds(getDoc(doc(patient,'medication_actions/4503599627370511')));
  await assertSucceeds(setDoc(doc(patient,'medication_actions/4503599627370511'),{...action,id:4503599627370511,uid:'4503599627370511'}));
  await assertFails(setDoc(doc(care,'medication_actions/21'),{...action,id:21}));
  await assertFails(setDoc(doc(patient,'medication_actions/21'),{...action,id:21,patientId:99}));
  await assertFails(setDoc(doc(patient,'medication_actions/21'),{...action,id:21,medicationId:'11'}));
  await assertFails(setDoc(doc(patient,'medication_actions/21'),{...action,id:21,medicationId:999}));
  await assertFails(updateDoc(doc(patient,'medication_actions/20'),{id:99}));
  await assertFails(updateDoc(doc(patient,'medication_actions/20'),{timestamp:999}));
  await assertSucceeds(updateDoc(doc(patient,'medication_actions/20'),{action:'snoozed'}));
  await assertFails(updateDoc(doc(patient,'users/patient'),{id:99}));
  await assertFails(updateDoc(doc(patient,'users/patient'),{retiredMedicationIds:[999]}));
  await assertFails(updateDoc(doc(care,'users/patient'),{retiredMedicationIds:[999]}));
  await assertFails(setDoc(doc(care,'moods/99'),{id:99,patientId:2,patient_uid:'care'}));
  await assertFails(setDoc(doc(patient,'medications/99'),{id:99,patientId:7,patient_uid:'patient',caregiverId:7,caregiver_uid:'patient'}));
  await assertSucceeds(setDoc(doc(patient,'moods/4503599627370512'),{id:4503599627370512,patientId:7,patient_uid:'patient',date:'2026-10-13',timestamp:1000}));
  await assertSucceeds(setDoc(doc(care,'medications/4503599627370513'),{id:4503599627370513,patientId:7,patient_uid:'patient',caregiverId:2,caregiver_uid:'care'}));
  await assertSucceeds(setDoc(doc(patient,'refill_requests/4503599627370514'),{id:4503599627370514,patientId:7,patient_uid:'patient',caregiverId:2,caregiver_uid:'care',medicationId:4503599627370513}));
  await assertSucceeds(runTransaction(care,async transaction=>{
    const reference=doc(care,'appointments/4503599627370515');
    if ((await transaction.get(reference)).exists()) throw new Error('Unexpected collision');
    transaction.set(reference,{id:4503599627370515,patientId:7,patient_uid:'patient',caregiverId:2,caregiver_uid:'care'});
  }));
  await assertFails(setDoc(doc(patient,'record_id_counters/moods'),{lastId:999}));
 }finally{await env.cleanup();}
});
