-- The questions the fleet backend / a dashboard asks Tiger Data.

-- 1. Scam weather, last 24 hours (from the continuous aggregate).
SELECT * FROM hourly_scam_weather
WHERE hour > now() - INTERVAL '24 hours'
ORDER BY hour DESC, scans DESC;

-- 2. Repeat offenders: senders with the most dangerous scans this week.
SELECT sender,
       COUNT(*)          AS dangerous_scans,
       MAX(risk)         AS worst_risk,
       MAX(ts)           AS last_seen
FROM scan_events
WHERE ts > now() - INTERVAL '7 days' AND risk >= 60
GROUP BY sender
ORDER BY dangerous_scans DESC, worst_risk DESC
LIMIT 20;

-- 3. Risk trend: is this week's smish wave worse than last week's?
SELECT date_trunc('day', ts) AS day,
       COUNT(*)               AS scans,
       ROUND(AVG(risk), 1)    AS avg_risk
FROM scan_events
WHERE ts > now() - INTERVAL '14 days'
GROUP BY day
ORDER BY day;
