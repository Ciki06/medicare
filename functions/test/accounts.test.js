const test = require('node:test');
const assert = require('node:assert/strict');
require('../index');
const {
  normalizeEmail,
  isValidEmail,
  isSelf,
  canManageEmail,
  emailChangeError,
} = require('../accounts')._test;

test('emails are trimmed, lowercased and validated', () => {
  assert.equal(normalizeEmail('  Caregiver@Example.COM '), 'caregiver@example.com');
  assert.equal(normalizeEmail(null), '');
  assert.ok(isValidEmail('caregiver@example.com'));
  assert.ok(!isValidEmail('caregiver@example'));
  assert.ok(!isValidEmail('caregiver @example.com'));
  assert.ok(!isValidEmail(''));
  assert.ok(!isValidEmail('a@b.c'.padEnd(255, 'x')));
});

test('a caregiver may only repoint the accounts it manages', () => {
  const target = {caregiverId: 'care-1'};
  assert.ok(isSelf('care-1', 'care-1'));
  assert.ok(!isSelf('care-1', 'patient-1'));
  assert.ok(canManageEmail('care-1', 'caregiver', 'patient-1', target));
  assert.ok(canManageEmail('care-1', 'caregiver', 'care-1', {caregiverId: null}));
  assert.ok(!canManageEmail('care-1', 'patient', 'patient-1', target));
  assert.ok(!canManageEmail('care-2', 'caregiver', 'patient-1', target));
  assert.ok(!canManageEmail('care-1', 'caregiver', 'patient-1', null));
});

test('auth failures are reported with actionable codes', () => {
  const code = e => emailChangeError(e).code;
  assert.equal(code({code: 'auth/email-already-exists'}), 'already-exists');
  assert.equal(code({code: 'auth/user-not-found'}), 'not-found');
  assert.equal(code({code: 'auth/invalid-password'}), 'invalid-argument');
  assert.equal(code({code: 'auth/user-token-expired'}), 'unauthenticated');
  assert.equal(code({code: 'auth/invalid-id-token'}), 'unauthenticated');
  assert.equal(code({code: 'auth/too-many-requests'}), 'resource-exhausted');
  assert.equal(code({code: 'auth/internal-error'}), 'internal');
});