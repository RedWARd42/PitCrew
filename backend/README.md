# Swat fleet backend — MongoDB Atlas

The shared blocklist and report store behind Swat: when a user taps
**Block & Report**, the app files the incident here, and the sender
lands on a community blocklist every Swat install can read. Built for
the **[MLH] Best Use of MongoDB Atlas** track.

## Data model

- `reports` — one document per incident (`incidentId` unique):
  sender, risk score, verdict, the drones' top flags, reporting
  account, timestamp.
- `blocklist` — one document per sender (`sender` unique): report
  counter (`$inc`), worst risk score seen (`$max`), first/last seen.

## Run it (5 minutes, free tier)

1. Create a free **M0 cluster** at cloud.mongodb.com (no card needed),
   a database user, and allow your IP under Network Access.
2. Copy the connection string and run:

   ```sh
   cd backend
   npm install
   MONGODB_URI='mongodb+srv://<user>:<pass>@<cluster>/swat' npm start
   ```

3. Smoke-test:

   ```sh
   curl localhost:8787/health
   curl -X POST localhost:8787/reports -H 'Content-Type: application/json' \
     -d '{"incidentId":"INC-2026-0001","sender":"+1 872-555-0147","riskScore":100,"verdict":"Scam likely","topFlags":["Angler: Lookalike sender"]}'
   curl localhost:8787/blocklist
   ```

4. Point the app at it:

   ```sh
   flutter run --dart-define=FLEET_BACKEND_URL=http://<host>:8787
   ```

   Unset, the app behaves exactly as before (fully on-device).

## Tests

```sh
npm test   # validation + document shaping (no database needed)
```

## Deploy

See `../deploy/` — a Dockerfile + compose file sized for a small
Vultr instance ([MLH] Best Use of Vultr).
