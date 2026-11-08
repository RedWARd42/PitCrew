import assert from 'node:assert/strict';
import { scanEventRow, scanEventParams, INSERT_SCAN_EVENT } from '../tiger.mjs';

const report = {
  sender: '+1 872-555-0147',
  riskScore: 100,
  verdict: 'SCAM — BLOCK & REPORT',
  topFlags: ['Scanner: QR code', 'Angler: Lookalike sender', 'Angler: Not a short code'],
};

const row = scanEventRow(report, new Date('2026-11-08T12:00:00Z'));
assert.equal(row.sender, report.sender);
assert.equal(row.risk, 100);
assert.equal(row.drones_flagged, 2, 'distinct drones, not flag count');
assert.equal(row.channel, 'sms');

assert.deepEqual(scanEventParams(report, row.ts), [
  row.ts,
  report.sender,
  100,
  report.verdict,
  2,
  'sms',
]);
assert.match(INSERT_SCAN_EVENT, /INSERT INTO scan_events/);
assert.equal(scanEventRow({ ...report, topFlags: undefined }).drones_flagged, 0);

console.log('backend tiger-sink tests passed');
