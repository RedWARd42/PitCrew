# Fleet Line on Twilio (replaces the Photon line)

The fleet gets a real phone number. Calls to it are screened by a
Twilio Function: blocked callers are rejected before the phone ever
rings, and the user gets a spoken alert call about it. Everyone else
rings through. (This is the Twilio redo of the earlier Photon/Spectrum
Fleet Line, which is not used.)

## Pieces

- `swat-call-block/inbound.js` — the Function. Block + alert logic;
  the alert call is Squeek's `sendAlert` pattern (Twilio Calls API,
  `Polly.Joanna-Neural` said twice, 20s timeout), no ElevenLabs, no
  Supabase.
- The app shows the number in the Drone Bay (**Fleet Line · Twilio**)
  when launched with `--dart-define=TWILIO_FLEET_NUMBER=+1...`.

## Set up (Twilio Console)

1. **Account + number**: sign up at twilio.com, buy a **Voice**
   number. Note the Account SID, Auth Token, and the number — they
   live in Twilio/your password manager, never in this repo.
2. **The blocker**: Functions and Assets → Services → Create Service,
   name it `swat-call-block`. Add Environment Variables:
   - `USER_PHONE=+1XXXXXXXXXX` — your real phone
   - `BLOCKED_NUMBERS=+12145550111,+12145550122`
   
   Add a Function at path `/inbound` with the contents of
   `swat-call-block/inbound.js`. **Deploy All.**
3. **Point the number at it**: Phone Numbers → Manage → Active
   Numbers → your number → Voice Configuration → *A call comes in*:
   **Function**, service `swat-call-block`, environment `ui`, path
   `/inbound`. Save.

## Test

- Call the Twilio number from a `BLOCKED_NUMBERS` number → rejected
  instantly; your phone then gets the spoken alert call.
- Call from any other number → rings through to you.
- Block someone new: edit `BLOCKED_NUMBERS` in the Function's env
  vars and redeploy. (Manual by design — no app/backend sync.)

## The honest limit

This screens calls **to the Twilio number only**. Calls straight to
your personal SIM are screened on the phone itself (the Calls tab /
block list in the app) — Twilio can't intercept those.
