# Live integration setup

The local demo needs no remote account. Do not point demo resets at operational systems.

## Supabase

Apply `supabase/migrations/202611080001_contracts.sql` to the existing project, then configure `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in root `.env`. Set `DEMO_MODE=0` to enable server snapshot persistence and restart the app. Server initialization hydrates the snapshot. The migration is idempotent, enables RLS, revokes public access, grants service-role CRUD, and adds operational tables to realtime. No migration is automatically applied by application startup.

The existing project has now passed the server Data API insert/upsert/read/delete check and the actual app store hydration/save/reload check. Root `.env` enables persistence with `DEMO_MODE=0`, keeps `DEMO_CACHE=only` and `COMMS_MODE=terminal`, and contains a local `DIRECTOR_TOKEN`. Restart the dev server to load these settings, then enter that token in the app's sign-in prompt. Do not copy the token into chat.

Run `pnpm supabase:verify` to check a unique temporary snapshot; it is removed afterward. `pnpm supabase:verify -- --initialize --app-roundtrip` also initializes `dal-1` only if absent and verifies the real store using a no-change pause command with an audit entry. Existing site contents are preserved. For a read-only catalog check of every table's RLS, grants and publication membership, run `supabase/verify.sql` in the SQL Editor. That catalog audit requires SQL access and has not been verified through the Data API.

The current backend persists the validated full plant snapshot. Per-entity tables and realtime publication establish the future normalized adapter contract; field updates currently use the Core API’s SSE stream. Production needs per-user authentication, per-site permissions, and transactional multi-worker coordination.

## NVIDIA

Set the API key and accessible model IDs (`NEMOTRON_MODEL`, optionally `NEMOTRON_REASONING_MODEL`, `NEMOTRON_VISION_MODEL`). Switch Director cache policy to prefer/live. The deterministic outcome appears first; narration can arrive later and never changes GO/HOLD. Only successful model results are recorded in cache. A cache miss uses an honestly labeled deterministic fallback.

Source checks: [AI SDK tools](https://ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling), [NVIDIA Nano model card](https://build.nvidia.com/nvidia/nemotron-3-nano-30b-a3b). The planned Nano free endpoint is marked deprecated; confirm availability in the account before rehearsal.

## Photon messaging

The configured account is Beta 2.0. Use [Photon destination and credential setup](photon-setup.md) for this project. The app selects the matching adapter from the project ID; the legacy instructions below apply only to a separate Stable Spectrum project.

1. Configure Stable project ID/secret, webhook secret, and an iMessage line. Beta `pho_prj_` project IDs are rejected to prevent mixing APIs.
2. Configure a public authenticated HTTPS `APP_URL`. App cards must not point to localhost.
3. Set `PHOTON_PEOPLE_JSON` to a JSON map of person ID to opted-in E.164 number. Example shape: `{"maria":"+15550000001","dev":"+15550000002"}` (replace fictional numbers). Include each opted-in recipient in the comma-separated `PHOTON_RECIPIENT_ALLOWLIST`.
4. Set `COMMS_MODE=live`. Restart. Warnings enqueue cards, then the delivery adapter sends a minimal brief, app card and ownership poll. The same card is edited on subsequent updates. Full operational evidence remains inside the authenticated app.
5. Point the project webhook at `/api/photon/webhook`. The SDK validates the raw-body HMAC and replay window. Text ownership uses `own WARNING_ID your next action and deadline`. Only the assigned contact can acknowledge. Poll selection prompts action; a concrete read-back is still required.

Delivery failures remain visibly failed. Do not assume a mirror message reached a phone. Provider messages/cards and webhook dedupe are tracked in process memory for the local build; production requires a durable outbox and provider ID storage. Read receipt ingestion and cross-provider group membership need live account verification.

Source checks: [Stable getting started](https://photon.codes/docs/spectrum-ts/getting-started), [app cards](https://photon.codes/docs/spectrum-ts/content/app), [webhook verification](https://photon.codes/docs/spectrum-ts/webhooks).

## ElevenLabs voice

The voice provider is now ElevenLabs Agents. The compressed 45-second ladder produces a simulated call unless `VOICE_MODE=live` is explicitly configured. The implemented outbound SIP adapter and scoped context/note/read-back tools require an ElevenLabs agent, imported Photon SIP phone-number ID, credentials, a public app URL and opted-in recipient. See [ElevenLabs setup](elevenlabs.md). No live call has been placed; account-side configuration and rehearsal remain required. LiveKit is no longer needed.
