import assert from 'node:assert/strict';
import { validateReport, reportDocument } from '../validate.mjs';

const good = {
  incidentId: 'INC-2026-1234',
  sender: '+1 872-555-0147',
  riskScore: 100,
  verdict: 'Scam likely',
  topFlags: ['Angler: Lookalike sender (+30)'],
  account: 'Ryan',
};

assert.equal(validateReport(good), null);
assert.match(validateReport(null), /object/);
assert.match(validateReport({ ...good, incidentId: '' }), /incidentId/);
assert.match(validateReport({ ...good, sender: 42 }), /sender/);
assert.match(validateReport({ ...good, riskScore: 101 }), /riskScore/);
assert.match(validateReport({ ...good, riskScore: -1 }), /riskScore/);
assert.match(validateReport({ ...good, topFlags: 'x' }), /topFlags/);

const doc = reportDocument(good, new Date('2026-11-08T12:00:00Z'));
assert.equal(doc.incidentId, 'INC-2026-1234');
assert.equal(doc.riskScore, 100);
assert.equal(doc.reportedAt.toISOString(), '2026-11-08T12:00:00.000Z');
assert.equal(reportDocument({ ...good, account: undefined }).account, null);
assert.equal(
  reportDocument({ ...good, topFlags: Array(20).fill('f') }).topFlags.length,
  8,
  'flags are capped at 8',
);

console.log('backend validation tests passed');
