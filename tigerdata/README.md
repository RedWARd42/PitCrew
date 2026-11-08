# Tiger Data — fleet scan telemetry

**[MLH] Best Use of Tiger Data.** MongoDB Atlas (see `../backend/`)
holds the blocklist; Tiger Data holds the *stream*: one time-series
row per scan, rolled up hourly into a "scam weather" view — volume,
average risk, repeat senders.

## Set up (free tier)

1. Create a Tiger Cloud service (console.cloud.tigerdata.com) — the
   free tier is enough; TimescaleDB comes built in.
2. Apply the schema and (optionally) the demo seed:

   ```sh
   psql "$TIGERDATA_URL" -f schema.sql
   psql "$TIGERDATA_URL" -f seed.sql
   ```

3. Run the analytics in `queries.sql` — the hourly rollup, repeat
   offenders, and the two-week risk trend.

## Live wiring

The fleet backend doubles as the ingest path: when `TIGERDATA_URL`
is set alongside `MONGODB_URI`, every `POST /reports` also inserts a
`scan_events` row (sender, risk, verdict, flag count) — see
`../backend/tiger.mjs`. Unset, nothing changes.
