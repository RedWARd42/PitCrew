# HackUTD 2026 — prize-track map (branch: `mlh-tracks`)

Every track labeled **[MLH]** on the HackUTD 2026: ZeroDay Devpost,
what Swat does for it, and the one step that is yours (accounts and
keys are always yours to create — nothing here was signed up for
you). Per the Devpost rules, **[MLH] tracks have no entry limit**;
sponsor tracks are capped at three per team.

| Devpost track | Status on this branch | Your activation step |
| --- | --- | --- |
| [MLH] Best Use of MongoDB Atlas | **Integrated** — `backend/` (Node + Atlas): Block & Report mirrors each incident into a `reports` collection and upserts the sender onto a shared community blocklist (report counter + worst risk). App hook: `lib/services/fleet_backend.dart`. Validation + document tests pass without a DB. | Create a free M0 Atlas cluster, set `MONGODB_URI`, run the backend (or deploy it), relaunch with `--dart-define=FLEET_BACKEND_URL=<url>`. |
| [MLH] Best Use of Gemini API | **Integrated** — verdict panel gains a **Gemini second opinion**: Gemini reads the fleet's findings and answers in ≤60 plain words, labeled as cloud AI next to the on-device verdict. `lib/services/gemini_service.dart` + prompt/parser tests. | Get a free key in Google AI Studio; relaunch with `--dart-define=GEMINI_API_KEY=<key>`. |
| [MLH] Best Use of Tiger Data | **Integrated** — `tigerdata/`: `scan_events` hypertable + continuous-aggregate hourly **scam-weather** rollup + retention policy, seeded with the calibrated demo scans. Backend mirrors each report into it when `TIGERDATA_URL` is set (telemetry can never fail a report). | Create a free Tiger Cloud service, apply `tigerdata/schema.sql`, set `TIGERDATA_URL` on the backend. |
| [MLH] Best Use of Vultr | **Ready to deploy** — `deploy/`: Dockerfile + compose + cloud-init that stage the fleet backend on a small Vultr instance; the Atlas secret stays a manual step by design. | Create the instance with the MLH credits, paste `deploy/cloud-init.yaml` as user data, set `.env`, `docker compose up`. |
| [MLH] Best Use of Solana | **Integrated (devnet prototype)** — `solana/`: blocked senders are SHA-256 fingerprinted (digits-normalized; raw numbers never go on-chain) and anchored as Solana Memo transactions, making the blocklist publicly verifiable. Fingerprint/payload tests pass. | Create + fund a devnet keypair (faucet), set `SOLANA_KEYPAIR_PATH`, run `npm run anchor`. |
| [MLH] Best Domain Name from GoDaddy Registry | **Skipped** — Ryan passed on this track (Nov 8); not entered. | — |
| [MLH] Build Your Hackathon A-Team with SpaceXSI | **Not claimed — honestly.** The track requires Cursor as the core coding agent plus a Grok Bot automation. Swat was built in VS Code with Muse + Copilot CLI, so we don't qualify and won't pretend to. | Only claimable if you actually build with Cursor + Grok Bot. |

## Bonus: sponsor track restored on this branch

- **Photon Track** (sponsor track, not [MLH]) — the Photon Fleet
  Line (Spectrum service in `photon/`, fleet number in the app) was
  built earlier and removed from `main` at the team's direction;
  this branch restores it from local history so it can be entered
  alongside T-Mobile if wanted. It goes live only with your Photon
  project + phone number. Remember the three-sponsor-track cap:
  T-Mobile + Photon leaves one slot.

## Also already on board (not [MLH] at HackUTD this year)

- **ElevenLabs** voices for every drone (`voice-streaming` work,
  included in this branch's base) — ElevenLabs is an MLH track at
  some events but is **not** listed at HackUTD 2026, so it supports
  the demo rather than a track entry.
