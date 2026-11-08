import assert from 'node:assert/strict';
import {
  normalizeSender,
  fingerprintSender,
  buildMemoPayload,
} from '../anchor.mjs';

// Formatting never changes identity.
assert.equal(normalizeSender('+1 (872) 555-0147'), '18725550147');
assert.equal(
  fingerprintSender('+1 872-555-0147'),
  fingerprintSender('18725550147'),
);
assert.match(fingerprintSender('456'), /^[0-9a-f]{64}$/);
assert.notEqual(fingerprintSender('456'), fingerprintSender('+1 872-555-0147'));

// The payload carries the fingerprint — never the raw sender.
const payload = buildMemoPayload('+1 872-555-0147', 100, 'INC-2026-1234');
assert.ok(payload.startsWith('SWAT1|'));
assert.ok(payload.includes('|100|INC-2026-1234'));
assert.ok(!payload.includes('872'), 'raw sender must never go on-chain');
assert.ok(Buffer.byteLength(payload) < 566, 'within the Memo size limit');

console.log('solana anchor tests passed');
