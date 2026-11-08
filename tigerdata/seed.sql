-- Seed rows: the six demo-inbox scans at their calibrated scores, so
-- the rollups have something to chew on the moment the schema lands.
-- (Synthetic demo data only — the same senders the app ships with.)

INSERT INTO scan_events (ts, sender, risk, verdict, drones_flagged, channel) VALUES
  (now() - INTERVAL '5 hours', '+1 872-555-0147', 100, 'SCAM — BLOCK & REPORT', 6, 'sms'),
  (now() - INTERVAL '5 hours', '456',               0, 'LOOKS LEGIT',           0, 'sms'),
  (now() - INTERVAL '4 hours', '+1 646-555-0119',  68, 'SCAM — BLOCK & REPORT', 3, 'sms'),
  (now() - INTERVAL '3 hours', '+1 800-555-0143',  64, 'SCAM — BLOCK & REPORT', 3, 'sms'),
  (now() - INTERVAL '2 hours', 'Mom',               0, 'LOOKS LEGIT',           0, 'sms'),
  (now() - INTERVAL '1 hour',  '+1 872-555-0147', 100, 'SCAM — BLOCK & REPORT', 6, 'overlay');
