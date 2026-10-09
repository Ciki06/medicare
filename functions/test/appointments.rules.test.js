const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc} = require('firebase/firestore');

test('patients can only mark their own appointments completed', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-medicare',
    firestore: {
      rules: fs.readFileSync(
        path.join(__dirname, '../../firestore.rules'),
        'utf8',
      ),
    },
  });

  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, 'users/patient'), {role: 'patient'});
      await setDoc(doc(db, 'users/other-patient'), {role: 'patient'});
      await setDoc(doc(db, 'users/caregiver'), {role: 'caregiver'});
      await setDoc(doc(db, 'appointments/patient-appointment'), {
        patientId: 'patient',
        caregiverId: 'caregiver',
        title: 'Clinic visit',
        status: 'scheduled',
      });
      await setDoc(doc(db, 'appointments/other-appointment'), {
        patientId: 'other-patient',
        caregiverId: 'caregiver',
        title: 'Other clinic visit',
        status: 'scheduled',
      });
    });

    const patientDb = env.authenticatedContext('patient').firestore();
    const otherPatientDb = env.authenticatedContext('other-patient').firestore();
    const caregiverDb = env.authenticatedContext('caregiver').firestore();

    await assertSucceeds(
      updateDoc(doc(patientDb, 'appointments/patient-appointment'), {
        status: 'completed',
      }),
    );
    await assertFails(
      updateDoc(doc(patientDb, 'appointments/patient-appointment'), {
        title: 'Changed by patient',
      }),
    );
    await assertFails(
      updateDoc(doc(patientDb, 'appointments/patient-appointment'), {
        status: 'scheduled',
      }),
    );
    await assertFails(
      updateDoc(doc(otherPatientDb, 'appointments/patient-appointment'), {
        status: 'completed',
      }),
    );
    await assertSucceeds(
      updateDoc(doc(caregiverDb, 'appointments/other-appointment'), {
        title: 'Caregiver edited visit',
      }),
    );
  } finally {
    await env.cleanup();
  }
});
