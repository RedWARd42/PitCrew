# Implementation checkpoint

The local seeded application is implemented and runs without credentials. Live services require a separate account-backed rehearsal; none are silently used in demo mode.

Verification: 79 unit/API/access-boundary/provider/proxy tests and S1–S5 golden evaluations pass, with TypeScript and ESLint clean. The original production build passes; the current voice/webhook changes have been typechecked and tested. PitCrew is running on local port 3000 behind a background ngrok endpoint; public health JSON matches localhost and public HTML is confirmed as PitCrew. The proxy-origin login fix passed with the actual token only on localhost and a non-secret invalid token through ngrok. Photon destination configuration matches the app, a synthetic signed webhook was accepted, and tampering was rejected. Actual Photon-origin delivery, browser visual acceptance and real-device checks remain unverified.

| Area | Implemented | Remaining live verification or stretch |
| --- | --- | --- |
| Contracts | Zod data/commands/events/tools, OpenAPI, migration, seed formats | Normalized DB adapter beyond snapshot persistence |
| Field | Shift, risk-ranked rounds, asset details, reading keypad, browser voice note capture, warnings/read-back, procedures/HOLD/override, I-PASS, incident, topology, theme, PWA | Device microphone compatibility and real iPhone QR rehearsal |
| Presenter | Director clock/reset/scenarios/cache, trace viewer, phone mirror, tag wall/print | Real demo phone recipients and backup recording |
| Simulation | Repeatable S1–S5, seeded plant, pausable 1 Hz clock, deterministic engine tests | BACnet/Modbus/Redfish adapters are future integrations |
| Agents | Event workflows, safe read tools and audited work mutations, optional hosted model tool loop, cached/live/fallback labels, structured outputs | NVIDIA account model availability and live latency/reasoning settings |
| Compiler | Six realistic source PDFs, SHA-256 source matching, bounded multipart upload, unapproved review output, optional vision extraction | Live model PDF support; qualified approval workflow is P1 |
| Supabase | User applied migration; Data API insert/upsert/read/delete verified; fictional site initialized; actual store save/load verified; local persistence configured | SQL catalog audit of all RLS/grants/realtime settings still requires SQL tools or SQL Editor |
| Communications | Compressed ladder; version-aware Stable/Beta adapters; Beta signed webhook, scoped ownership, delivery/failure and call lifecycle events; read-only account inspector | Real phone delivery rehearsal, read-receipt/poll callbacks, cross-provider incident group lifecycle |
| Voice | ElevenLabs SIP outbound adapter; per-call context/note/read-back tools; opt-in/mode gates; durable dispatch reservation; simulated default | ElevenLabs account/agent/imported Photon SIP line setup and real call rehearsal; inbound caller-verification flow |
| Stretch | Adapter boundaries and deploy packaging | AR, gauge vision, Brev hosting, fine tuning |

Live claims must match a completed rehearsal. The original `DEMO_SCRIPT.md` describes the target presentation, including features that still need external setup. Use the phone mirror and deterministic labels while presenting the offline version.

## Resume after connector refresh

1. Supabase plugin skills are available, but SQL/project tools are still not exposed in this chat.
2. The user applied the migration to existing project `hrkuvnanhchdvinviaii`. No new project was created.
3. Server snapshot insert/upsert/read/delete and actual app store persistence passed. `dal-1` was initialized only if absent.
4. Root `.env` now enables persistence and has a local access token; model calls and outbound messaging remain disabled. Restart the dev server and sign in with the local `DIRECTOR_TOKEN`.
5. Run `supabase/verify.sql` when SQL access is available to inspect the full RLS/grant/publication catalog. Rehearse NVIDIA and opted-in Photon separately with a public authenticated HTTPS app URL; configure SIP separately for voice.

The code and verification instructions are in the repository. Default `pnpm demo` remains local and safe to rehearse without credentials.
