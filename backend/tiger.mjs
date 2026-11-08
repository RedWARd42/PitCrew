// Optional Tiger Data sink ([MLH] Best Use of Tiger Data): when
// TIGERDATA_URL is set, each filed report also becomes one row in the
// scan_events hypertable (schema in ../tigerdata/), feeding the
// hourly "scam weather" rollups. Pure row shaping lives here so it
// can be unit-tested; the pg client is created lazily by server.mjs.

export function scanEventRow(report, now = new Date()) {
  return {
    ts: now,
    sender: report.sender,
    risk: report.riskScore,
    verdict: report.verdict,
    drones_flagged: Array.isArray(report.topFlags)
      ? new Set(report.topFlags.map((f) => String(f).split(':')[0])).size
      : 0,
    channel: 'sms',
  };
}

export const INSERT_SCAN_EVENT =
  'INSERT INTO scan_events (ts, sender, risk, verdict, drones_flagged, channel) ' +
  'VALUES ($1, $2, $3, $4, $5, $6)';

export function scanEventParams(report, now = new Date()) {
  const r = scanEventRow(report, now);
  return [r.ts, r.sender, r.risk, r.verdict, r.drones_flagged, r.channel];
}
