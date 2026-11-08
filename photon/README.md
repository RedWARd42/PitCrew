# Swat Fleet Line — Photon 2.0 (Spectrum)

The drone fleet, living where people already talk. This service puts
Swat on **Photon 2.0** via the `spectrum-ts` SDK:

- **Text the fleet** — iMessage the fleet line (and any other channel
  enabled in the Photon dashboard: SMS/RCS, WhatsApp, Telegram) with a
  suspicious message; the six drones scan it and reply in the same
  conversation. Add `from +1 …` as a first line to include the sender,
  reply `ask Link` (any drone) for one specialist's take, `help` for
  instructions.
- **Call the fleet** — voice-to-voice on the fleet's SMS number: a
  Voice profile routes the call over SIP to a voice provider
  (Retell / ElevenLabs / LiveKit / Twilio) running the on-duty drone
  prompt in `voice/RETELL.md`.

The brain (`src/fleet.ts`) is a 1:1 TypeScript port of the Flutter
app's Dart engine — same checks, same scoring, same calibration
(T-Mobile smish 100, real 456 bill 0, Chase 68, USPS 64; `npm test`
proves it).

## Setup (one time, ~10 minutes)

1. **Photon dashboard** — app.photon.codes → create a project.
   - Add an **iMessage line** (the flagship text channel).
   - Add an **SMS number** (voice lives on this one).
   - Settings → copy the **project ID** and **secret**.
2. **Configure** — `cp .env.example .env`, fill in
   `SPECTRUM_PROJECT_ID`, `SPECTRUM_PROJECT_SECRET`, and
   `PHOTON_FLEET_NUMBER` (the SMS number, for reference).
3. **Run** — `npm install`, then `npm start`
   (or `npx tsx --env-file=.env src/index.ts` to load `.env`).
   With no credentials set, the terminal provider runs locally so the
   conversation loop works with zero setup; set `PHOTON_TERMINAL=1`
   to keep it alongside iMessage.
4. **Voice** — follow `voice/RETELL.md`: Voice profile on the SMS
   number → SIP → your voice provider with the fleet prompt.
   `npm run voice:config` prints the SIP block to paste.
5. **In the app** — run Flutter with
   `flutter run --dart-define=PHOTON_FLEET_NUMBER=+1XXXXXXXXXX`
   and the Drone Bay's Fleet Line card gets working **Text the fleet**
   and **Call the fleet** buttons dialing that number. Without the
   define, the card shows the setup steps instead of a fake number.

## Files

- `src/index.ts` — Spectrum app: providers, message loop, per-space
  conversation state (a later `from +1 …` re-runs the sender check).
- `src/fleet.ts` — the fleet brain (port of the app engine) + chat
  formatting + per-drone answers.
- `src/fleet.test.ts` — calibration tests against the app's demo inbox.
- `src/voice-config.ts` — SIP settings printer (`npm run voice:config`).
- `voice/RETELL.md` — voice provider setup + the on-duty drone prompt.

Honest limits: the service advises, it cannot block senders or place
calls itself (Photon voice calls are placed/answered by the SIP voice
provider, not the SDK). All demo data is synthetic.
