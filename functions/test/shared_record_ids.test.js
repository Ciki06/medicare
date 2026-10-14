'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {planAlignment, allocate} = require('../shared_record_ids');
function fixture() {
  const doc = (uid, data) => ({uid, data, updateTime: '2026-10-13T00:00:00Z'});
  return {projectId: 'medicare-348a1', collections: {
    users: [doc('care', {role:'caregiver'}), doc('patient-z', {role:'patient',caregiverId:'care'}), doc('patient-a', {role:'patient',caregiverId:'care'}), doc('family', {role:'family',linkedPatientIds:['patient-z']})],
    medications: [doc('med-z', {patientId:'patient-z',caregiverId:'care'})],
    appointments: [doc('apt', {patientId:'patient-z',caregiverId:'care'})],
    medication_actions: [doc('action', {patientId:'patient-z',medicationId:'deleted-med',syncStatus:'pending'})],
    moods: [doc('mood', {patientId:'patient-z'})],
    refill_requests: [doc('refill', {patientId:'patient-z',caregiverId:'care',medicationId:'med-z'})],
  }};
}
test('all scoped record document names and IDs are numeric; role IDs match relationships',()=>{
  const plan=planAlignment(fixture());
  for(const write of plan.writes){
    assert.equal(typeof write.data.id,'number');
    if(write.collection!=='users') assert.equal(write.document,String(write.data.id));
    for(const field of ['patientId','caregiverId','medicationId']) if(field in write.data) assert.equal(typeof write.data[field],'number');
  }
  const patient=plan.writes.find(w=>w.collection==='users'&&w.document==='patient-z');
  const appointment=plan.writes.find(w=>w.collection==='appointments');
  assert.equal(appointment.data.patientId,patient.data.id);
  assert.equal(appointment.data.patient_uid,'patient-z');
  const family=plan.writes.find(w=>w.document==='family');
  assert.deepEqual(family.data.linkedPatientIds,[patient.data.id]);
  assert.deepEqual(family.data.linkedPatientUids,['patient-z']);
});
test('historical medication IDs are kept in metadata without duplicate schedule collections',()=>{
  const plan=planAlignment(fixture());
  const action=plan.writes.find(w=>w.collection==='medication_actions');
  const id=plan.mappings.medications['deleted-med'];
  assert.equal(action.data.medicationId,id);
  assert.equal(action.data.syncStatus,'pending');
  assert.ok(plan.archivedMedicationIds.includes(id));
  assert.ok(plan.writes.every(write=>!['medication_keys','appointment_keys'].includes(write.collection)));
});
test('planning is deterministic and preserves already assigned integer IDs',()=>{
  const snapshot=fixture();snapshot.collections.users[1].data.id=42;
  assert.deepEqual(planAlignment(snapshot),planAlignment(snapshot));
  assert.equal(planAlignment(snapshot).mappings.patients['patient-z'],42);
  assert.throws(()=>allocate([{uid:'a',data:{id:1}},{uid:'b',data:{id:1}}]),/Duplicate/);
});
test('missing or wrong-role patients abort the plan instead of dropping history',()=>{
  const snapshot=fixture();snapshot.collections.moods[0].data.patientId='missing';
  assert.throws(()=>planAlignment(snapshot),/Missing patient/);
  snapshot.collections.moods[0].data.patientId='care';
  assert.throws(()=>planAlignment(snapshot),/Missing patient/);
});
test('a second plan preserves canonical IDs including deleted medication keys',()=>{
  const first=planAlignment(fixture());
  const snapshot={projectId:'medicare-348a1',collections:{}};
  for(const item of first.writes){
    (snapshot.collections[item.collection] ||= []).push({uid:item.document,data:item.data});
  }
  const second=planAlignment(snapshot);
  assert.equal(second.moves.length,0);
  for(const entity of ['medications','appointments','medication_actions','moods','refill_requests']){
    const before=first.writes.filter(item=>item.collection===entity);
    const after=second.writes.filter(item=>item.collection===entity);
    assert.deepEqual(after.map(item=>item.data),before.map(item=>item.data));
  }
});
