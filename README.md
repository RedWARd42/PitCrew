# Swat — Signal Swarm

A fleet of specialist drones that patrol your text messages. Built for the
T-Mobile **Safe Signal** prompt at HackUTD 2026: protect customers from
scams *before, during, and after* a threat — with the drone fleet as the
interface, not a dashboard bolted onto a classifier.

## The idea (a Clicky flip)

HeyClicky puts one AI buddy by your cursor. Swat flips it: **one drone per
scam type**, living over your messages. Instead of an opaque "spam score",
each specialist flies to the exact words it objects to, highlights them in
its own color, and — when tapped — walks you through what it found, one
tell at a time. The protection report writes itself as a byproduct.

| Drone | Color | Patrols for |
|---|---|---|
| Angler | orange | Spoofed senders (real brands use short codes, not random numbers) |
| Link | blue | Fake links (lookalike domains, shorteners, raw IPs, punycode) |
| Scanner | purple | QR codes — decodes where they actually point |
| Pressure | red | Urgency & threats ("suspended within 24 hours", "final notice") |
| Impersonator | pink | Impersonation & asks for PINs/passwords/payment rails |
| Swap | green | SIM-swap / port-out priming & verification-code fishing |

## The `Message-Detection` flow

1. **Inbox** — an Android-Messages-style thread view. On Android it reads
   the device's *real* SMS store (`READ_SMS`, on-device only); anywhere
   else it falls back to a synthetic demo inbox (hackathon rule: synthetic
   scam data only). The demo set includes a full-strength smishing text
   impersonating T-Mobile and the genuine article from short code **456**,
   so the fleet has to prove it can say "this one is fine", too.
2. **Release the Fleet** — all six drones launch at once, land beside the
   message in order, sweep a scan beam, and highlight their evidence in
   place. The risk score counts up with a confidence figure based on how
   many *independent* drones flagged something.
3. **Tap a drone** — its findings in plain English, plus **Walk me through
   it**: a step-by-step walkthrough that highlights each tell as it's
   explained (the narration text is written to be spoken; see
   `lib/services/walkthrough.dart`).
4. **Block & Report** — files the auto-written protection report (sender,
   score, per-drone evidence) and lands on the *after* checklist: SIM-swap
   lock, account PIN, family safe word.

## Emails tab — the fleet over the mail app

The same six drones scan email — where phishing still lives, and where
Signal Swarm began. Open a message in the Gmail-style inbox and the
reading view gets the full treatment: release the fleet, highlights in
place, **tap a drone → "Teach me — walk through it"**, Block & Report,
share with family. Email adds tells texts don't have, checked by the
email analyzer (`lib/services/email_analyzer.dart`):

* **Sending domain vs. display name** — "T-Mobile Billing" is free text;
  `billing@t-mobile-verify-secure.com` is the confession (Angler).
* **Reply-To mismatch** — From looks tidy, your reply goes to the
  scammer's domain (Angler).
* **Attachments** — dangerous types and double extensions like
  `invoice.pdf.exe` (Scanner), plus everything shared with texts: links,
  QR payloads, pressure, credential asks, code fishing.

The demo mailbox includes the original Signal Swarm scenario — a payroll
QR phish — next to a CEO gift-card fraud with *no link at all*, and a
genuine T-Mobile bill the fleet has to acquit.

## Blocked tab — what Swat stopped

Modeled on the incidents + block list in
[Squeek](https://github.com/syedkazmi14/squeek) (the team's Rowdy Hacks
winner): every blocked message stays visible with its risk score, the
drone categories that convicted it, its incident ID, and who blocked it —
and the list is **shared with the trusted contact**, so a sender Alex
blocks never reaches Maya either. Header stats: total blocked, reported
to T-Mobile, shared by family. Any block can be undone.

## Family tab — a trusted human, one tap away

Protection fails when the user faces a scam alone and pressured. The
Family tab is a dedicated thread with one trusted contact (demo: Alex,
Maya's son) built for that moment:

* **Share this scan** (on the PROTECTED panel) drops the fleet's full
  report card into the thread and jumps straight there — *check with a
  human before you act*, as a one-tap action, not advice in a pamphlet.
* **Quick actions for shaky hands**: "I'm being pressured" (one-tap SOS)
  and "Ask for the safe word". The safe word is pinned on the contact
  card: any "family emergency" that can't produce it isn't family.
* **Real escalation**: the call and SMS buttons hand off to the actual
  dialer / SMS composer with the contact's number (`swat/comms` channel)
  — the in-app thread is for scan-sharing, the phone call is for real
  emergencies.

Demo note: replies in the Family thread are canned on-device responses
that demonstrate the shape of the exchange; the share/scan/SOS mechanics
are real app state.

## Over the real Messages app (Android) — the primary surface

Swat's protection does not live inside Swat. Arm it once from the app bar
and a native foreground service (`OverlayService.kt`) patrols **over other
apps, including Google Messages**, using the system alert window:

1. A text arrives → `SmsReceiver` catches the broadcast → the overlay's
   **fleet scan panel opens right on top of Messages**: the message, all
   six drones lighting up one by one with their points, each drone's
   evidence highlighted in the text, then the verdict.
2. **Block & Report works from the panel itself** — the sender lands in
   the shared block list that Swat's Blocked tab reads.
3. "Teach me" jumps into Swat for the step-by-step walkthrough; the
   floating SWAT badge stays on patrol, and tapping it scans your latest
   text on demand.

The overlay runs a Kotlin port of the same engine (`KotlinScamAnalyzer.kt`
— same drones, same registry, same scoring; verified to match the Dart
engine's scores on the demo corpus). The message under scan comes from the
SMS broadcast / the device SMS store — the same store Messages reads.

Honest platform limits: an overlay can warn and act on its own surface,
but no Android API lets a third-party app reach into Messages to block a
tap or quarantine a text inside it — so Swat blocks at its own layer and
says so. iOS offers no overlay and no SMS-store access at all, which is
why this is an Android build (demoed on the emulator).

## Architecture

```
lib/
  models/message.dart          ChatMessage, Finding, MessageAnalysis (pure Dart)
  models/email.dart            EmailMessage (display name, domain, Reply-To…)
  models/family_and_blocked.dart  TrustedContact, BlockedEntry, chat messages
  services/scam_analyzer.dart  the detection engine — six drone analyzers,
                               brand registry (official domains + short codes),
                               span-accurate evidence, honest-confidence scoring
  services/email_analyzer.dart the fleet over email: sending-domain and
                               Reply-To checks + attachment scan, reusing the
                               text engine for links/QR/pressure/credentials
  services/walkthrough.dart    click-to-explain steps + auto protection report
  services/stores.dart         blocked list + family thread state (shared)
  services/device_services.dart  platform channels (SMS, overlay, comms)
  data/demo_inbox.dart         synthetic text scenarios
  data/demo_emails.dart        synthetic email scenarios
  screens/swat_shell.dart      Messages / Emails / Blocked / Family tabs
  screens/messages_screen.dart messages inbox, fleet flight/scan, verdict,
                               block & report, after-checklist, share-to-family
  screens/emails_screen.dart   mail inbox + reading view with the fleet over
                               it and "Teach me" walkthroughs
  screens/blocked_screen.dart  incidents + family-shared block list
  screens/family_screen.dart   trusted-contact thread: scan cards, SOS and
                               safe-word quick actions, call/SMS hand-offs
  widgets/drone_widget.dart    the drone itself (rotors, scan pulse, badges)
android/.../MainActivity.kt    swat/sms + swat/overlay + swat/comms hosts
android/.../OverlayService.kt  badge + fleet scan panel over other apps
android/.../KotlinScamAnalyzer.kt  the detection engine, ported to Kotlin
                               so the fleet runs inside the overlay
android/.../SmsReceiver.kt     incoming-text trigger for the overlay scan
android/.../SwatPrefs.kt       shared state: armed flag, last message,
                               native block list
test/                          engine tests (SMS + email), store tests,
                               app-shell smoke test
```

The engine is pure Dart with zero Flutter imports, so it is unit-tested
without a device and runs identically on real and synthetic messages.
Message content never leaves the phone.

## Run it

```bash
flutter pub get
flutter test          # engine + smoke tests
flutter run -d emulator-5554
```

For the full demo: start the overlay from the app bar (grant "Display
over other apps" plus the SMS permissions), open **Google Messages**, then
in the emulator's Extended Controls → Phone, send an SMS to the emulated
device from `+1 872-555-0147` with the smishing text. The fleet scan panel
opens **over Messages itself** — drones, highlights, verdict, Block &
Report — without ever entering Swat. Back in Swat, the same text is in
the inbox view and the overlay block shows in the Blocked tab.
