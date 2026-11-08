-- Swat scan telemetry on Tiger Data (TimescaleDB) — [MLH] Best Use of
-- Tiger Data.
--
-- Every fleet scan/report becomes one time-series row. Tiger Data's
-- hypertables + continuous aggregates turn that stream into a live
-- "scam weather" rollup: how much scam traffic is moving, how risky
-- it is, and which senders keep coming back.

CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS scan_events (
  ts             TIMESTAMPTZ NOT NULL,
  sender         TEXT        NOT NULL,
  risk           SMALLINT    NOT NULL CHECK (risk BETWEEN 0 AND 100),
  verdict        TEXT        NOT NULL,
  drones_flagged SMALLINT    NOT NULL DEFAULT 0,
  channel        TEXT        NOT NULL DEFAULT 'sms' -- sms | email | overlay
);

SELECT create_hypertable('scan_events', 'ts', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS scan_events_sender_idx
  ON scan_events (sender, ts DESC);

-- Hourly rollup, kept fresh by Tiger Data's continuous aggregates:
-- scan volume + average risk per verdict.
CREATE MATERIALIZED VIEW IF NOT EXISTS hourly_scam_weather
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', ts) AS hour,
       verdict,
       COUNT(*)              AS scans,
       ROUND(AVG(risk), 1)   AS avg_risk,
       COUNT(DISTINCT sender) AS distinct_senders
FROM scan_events
GROUP BY hour, verdict
WITH NO DATA;

-- Keep raw events for a year; the rollup keeps the long history.
SELECT add_retention_policy('scan_events', INTERVAL '365 days',
                            if_not_exists => TRUE);
