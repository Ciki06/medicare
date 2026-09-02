const test = require('node:test');
const assert = require('node:assert/strict');

const {fcmTokensForUser, chunks, stringValue} = require('../index')._test;

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
