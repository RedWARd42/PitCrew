# Photon project setup

The configured project uses Photon **Beta 2.0**, with API version `2026-07-01`. The app chooses the Beta adapter for `pho_prj_` IDs and retains the separate Stable Spectrum adapter only for legacy projects. Never place a Beta API key into a Stable Spectrum API call.

## Existing account information

Run `pnpm photon:info` to read the configured project's metadata, resources, users, voice profile, destinations and event catalog. The output report is `data/runtime/photon-setup.json`, ignored by Git. Signing secrets, passwords and tokens are redacted. No project settings are changed. Project API keys are read from `PHOTON_API_KEY`, or the existing `PHOTON_PROJECT_SECRET` variable for compatibility.

At inspection the project was named **hackutd2026-nmc** and had no default voice profile. That means SIP settings still need to be created/configured in the Photon dashboard before importing the line into ElevenLabs. Do not use the older Stable SIP username/password instructions for this Beta project. Webhook signing secrets are returned at destination creation and cannot be recovered by listing destinations.

## Destination settings

| Field | Value |
| --- | --- |
| Name | PitCrew |
| URL | `https://YOUR_PUBLIC_HOST/api/photon/webhook` |
| API version | `2026-07-01` |
| Message events | `message.received`, `message.delivered`, `message.failed` |
| Voice status events | `call.started`, `call.ringing`, `call.answered`, `call.connected`, `call.ended` |

Create the destination, copy its one-time `whsec_...` signing secret into `PHOTON_WEBHOOK_SECRET` in root `.env`, and restart the app. Do not use the project API key as the webhook signing secret. `message.received` carries incoming message content; read receipts may be represented as `message.read` content rather than a separately selectable webhook event. The current Beta handler processes text ownership replies, delivery/failure status and audits call lifecycle events; it does not infer a read receipt from a delivery event.

The handler verifies Standard Webhooks headers (`webhook-id`, `webhook-timestamp`, `webhook-signature`) against exact raw bytes with a five-minute replay window, validates the selected project/version, and deduplicates committed events in the audit log. Ownership text is `own WARNING_ID your next action and deadline`; only a configured opted-in contact who is the current owner can acknowledge.

## Local HTTPS tunnel

The local app runs on port 3000. Start it with `pnpm demo`, then use the installed ngrok client to forward that port. If the npm `ngrok` command silently exits on Windows, invoke the actual `ngrok.exe` under the installed package's `bin` directory instead. The ngrok account auth token belongs in the ignored root `.env` as `NGROK_AUTHTOKEN`; never paste it into chat. Use the printed public HTTPS origin as `APP_URL` and append `/api/photon/webhook` for the destination. Keep the tunnel running during testing; if its address changes, update both settings.

The app's normal APIs remain protected by `DIRECTOR_TOKEN`. The webhook route uses signature verification and voice tools use a separate per-call capability, so providers do not need the operator login token.

The app accepts its local request origin and the exact origin configured in `APP_URL`. This handles ngrok's HTTPS-to-localhost forwarding without accepting arbitrary cross-origin login or mutations. If the tunnel hostname changes, update `APP_URL` and restart PitCrew. The saved destination has been checked against the running public URL. A locally signed synthetic probe verified the receiving handler; it is not proof that the secret matches Photon or that a real provider event has been delivered.

## Enable real messaging separately

Set `PHOTON_PEOPLE_JSON` to a person-to-E.164-number mapping and add each opted-in number to `PHOTON_RECIPIENT_ALLOWLIST`. `PHOTON_SENDER_USER_ID` selects a project-owned iMessage agent when there is more than one; one agent is selected automatically if it is the only one in the returned user page. Enable `COMMS_MODE=live` only for a real rehearsal. Beta delivery currently sends a minimal text and authenticated deep link; Stable-only app-card APIs are not called with Beta credentials.

The account API key and MCP connection do not replace a configured sending line. Read-only inspection does not purchase or provision phone resources, send messages, or place calls.

References: [Photon API schema](https://api.photon.codes/openapi.json), [Photon MCP](https://photon.codes/docs/beta/ai-tools/mcp), [Standard Webhooks specification](https://github.com/standard-webhooks/standard-webhooks/blob/main/spec/standard-webhooks.md).
