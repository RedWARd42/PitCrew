# Groundtruth: Demo Script (≈4.5 minutes + Q&A)

## Setup
**Stage**
- Laptop → projector, showing the **phone mirror** of the field app (QuickTime or a mirroring app) on the left.
- The **Agent Trace Viewer** on the right.
- **Demo Director** hidden on a second laptop or tab.

**Props on the table/wall**
- Printed photos of **Chiller 3**, **UPS-2 / PDU-4**, and **Battery String 3**, each with a QR code (and an NFC sticker if available).

**People**
- **Presenter** (narrates).
- **"Maria"** (holds the field phone and plays the night-shift tech).
- **"Dev"**, the on-call chief. Either a teammate's iPhone, or, with permission, a **judge's phone** that we registered beforehand.

**Pre-flight (T-10 min)**
1. `pnpm demo`, then reset to the start state.
2. `DEMO_CACHE=prefer`.
3. Check that the Photon line sends to every phone.
4. Phones charged; Do Not Disturb **off** on Dev's phone.
5. Volume up for the call.
6. Backup video queued.

---

## 0:00–0:30 · The hook
**Presenter:**
> "In November 2025, the CME, the world's largest derivatives exchange, stopped trading for over ten hours. The cause was a cooling failure at a data center. The warning signs showed up about 16 hours before trading halted. In 2023, an Azure region went down after a power dip tripped its chillers. Three people were on the night shift, and the water got too hot to restart them.
>
> Across nine major outages we studied, the warning was almost always there. What failed was **who owned it, what got handed over, and what information people had when it mattered.**
>
> Today's tools watch equipment. Groundtruth manages the **work around the equipment**, for the technician on the floor."

---

## 0:30–1:15 · Scene 1: Shift start and smart rounds (missed warning → owned warning)
**Director:** start scenario **S1** (CH-3 drift, day-shift rattle note already logged).

1. Maria opens the app: **"You've inherited 3 items"**. Swipe through the handover cards and confirm each one (show the read-back).
2. The round list shows **Chiller 3 first**, with the chip **"Drift + open note"**.
3. Maria **taps the Chiller 3 tag** (QR or NFC) and the asset page opens instantly. On screen: the live state, the drift chip **"approach temp ↑1.5°F vs 5-day baseline"**, and the day shift's note "rattle near pump B".
4. Maria holds the voice button: *"Pump B still rattling, louder than yesterday."* The Field Scribe structures the note live.

**Right screen (Trace Viewer):** the **Investigator** plan appears and ticks off live:
- sensor sanity ✓
- sibling comparison ✓ (CH-1 and CH-2 are normal)
- recent work ✓
- notes ✓
- time-to-limit (days) ✓
- procedure found ✓
- owner chosen ✓

**Presenter:**
> "No one prompted that. Nemotron triggered on the event, planned, called seven tools, and produced an **owned warning** with evidence, a deadline and an owner."

---

## 1:15–2:00 · Scene 2: Procedure Guardian (wrong info at the wrong time)
**Director:** start **S2** (UPS-2 in bypass for planned work).

1. The redundancy pill turns amber: **"Hall 2 power: N+1 → N"**.
2. Maria taps the **PDU-4** tag and opens *"PDU-4 isolation"*. This procedure was a PDF; we show the original next to the **compiled steps** that Nemotron VL extracted, each with checkable preconditions.
3. Steps 1–5 show **GO**. At step 6, *"Open breaker B"*, a full-width **HOLD** appears: *"UPS-2 is in bypass. Opening breaker B removes Row D's last power source. Do not proceed. Safe alternative: wait for UPS-2 return-to-service, or transfer Row D to the alternate PDU first."*
4. Tap **Why?** to show the reasoning sheet, and point to the Trace Viewer: `get_live_state` → `get_active_work` → `simulate_action(open breaker B)` → Row D: 2 sources → 0.

**Presenter:**
> "The LLM doesn't guess about physics. A tested topology engine computes the impact, and Nemotron reasons over it and explains it. About 59% of human-error outages involve procedures not being followed. This catches the mistake at the step, before it happens."

---

## 2:00–3:30 · Scene 3: The 2 a.m. cascade (Photon, voice, and cross-organization handoff)
**Director:** start **S3**. A voltage dip trips CH-1 and CH-2, and standby CH-3 fails to auto-start.

1. **Projector:** the raw alarm counter jumps to **47 alarms in 90 seconds**, then collapses into **one incident card**: *"Voltage dip → CH-1/CH-2 trip; CH-3 failed auto-start."*
2. A **countdown ring** appears: *"≈14 min until CHW supply passes the restart limit"*, with its stated assumptions. The **EOP "Chiller restart after trip"** is surfaced, and Maria is the incident owner.
3. **Dev's phone buzzes.** An iMessage **app card** arrives showing the mini-trend, the countdown, the redundancy state and buttons (**Own / Need help / Dispatch vendor**). Show it on the projector via the in-app mirror if needed.
4. Dev **reads it but doesn't respond** (scripted). The app shows **"Read, not acknowledged"**, and after the compressed timer **Dev's phone rings**.
5. **Voice call (speaker on, so the room can hear):**
   > **Agent:** "Groundtruth for Dev. Severity one, Hall 2 cooling. Chillers 1 and 2 tripped on a voltage dip, and chiller 3 failed to auto-start. Chilled-water supply will pass the restart limit in about twelve minutes. Maria is on site and owns the restart procedure. Do you want me to engage the chiller vendor?"
   > **Dev:** "Yes. And what's the redundancy on power right now?"
   > **Agent:** "Power is at N. UPS-2 is still in bypass for planned work, so I'd hold that maintenance. Say 'I own escalation' to confirm."
   > **Dev:** "I own escalation."
6. Within seconds, an **incident group chat** appears: *"INC-0042 · Hall 2 cooling"*. It has its avatar set and members added by role: **Dev, Maria, the vendor engineer (WhatsApp/SMS), and the tenant contact**. The **pinned status message updates in place** as the countdown moves.
7. Maria restarts CH-3 per the EOP in the app. The countdown stops, and the agent posts the resolution to the group.

**Presenter:**
> "The handoffs that break real outages are between organizations: operator to tenant, vendor to operator. CME decided not to fail over partly because early information suggested a short outage. Here every party gets the same live picture, time-to-limit included. We used Photon app cards, read receipts, polls, group creation, renaming and membership, and voice. The agent escalated from a text to a call on its own, and captured a verbal read-back."

---

## 3:30–4:05 · Scene 4: Handover (unclear handoff → structured handoff)
**Director:** jump the clock to 06:00.

1. The Handover Writer drafts an **I-PASS** handover, **ordered by the incoming tech's walking route**:
   - CH-3 pump B (owned, vendor booked)
   - UPS-2 still in bypass (hold maintenance)
   - Incident INC-0042 resolved; review pending
2. The incoming tech receives it **on their phone by iMessage** before arriving, and confirms each critical item with a reply. The app shows the confirmations.

**Presenter:**
> "Hospitals cut medical errors 23% with this structured handoff format. Data centers mostly use spreadsheets and memory."

---

## 4:05–4:30 · Close
**Presenter:**
> "Groundtruth turns rounds, procedures and shift changes, the things techs already do, into an early-warning system. It keeps people in control: it advises, explains, and never touches the plant. Nemotron runs self-hosted on a Brev GPU, so plant data never has to leave the building. Every scene you saw maps to a real outage: CME, Azure, Korea's government data center fire, Heathrow. **Keep the world running: one owned warning at a time.**"

(Optional 10-second flourish, if built: hold the phone up to the Battery String 3 photo. **AR labels** float over it: *"Impedance +15% in 3 weeks — voltage still normal. Quarterly test would miss this."*)

---

## Q&A prep (likely questions)
- **"Who tags everything?"**
  - We tag only the critical infrastructure on rounds (dozens to a few hundred per site, at under $1 per tag).
  - We reuse the existing asset barcodes.
  - GPU and server issues route through tickets.
  - Tags are a shortcut, not a requirement: search, map and alarm deep links work too.
- **"Can you trust an LLM here?"**
  - It's advisory-only, and deterministic engines compute the physics.
  - Every decision has a trace.
  - Only 16% of operators accept automated changes, so we designed for the other 84%.
- **"Real data integration?"**
  - The `TelemetrySource` adapter boundary means BACnet/Modbus/SNMP/Redfish adapters plug in.
  - Our simulator mirrors real fault signatures (optionally calibrated on LBNL chiller fault data).
- **"Security of iMessage/SMS?"**
  - Messages carry minimal context plus authenticated deep links, and everything is audit-logged.
  - Enterprises can use WhatsApp Business or other channels, and self-hosted models.
- **"How is this different from Phaidra / DCIM vendors?"**
  - Those watch equipment for the control room.
  - We manage the work around the equipment for the floor technician (ownership, procedures, handover) across vendors and organizations.
- **"Why Nemotron?"**
  - Open weights for on-site deployment.
  - The model sizes match the jobs: Nano for high-volume workers, Super for reasoning, VL for documents.
  - Strong tool calling.
  - A switchable reasoning trace that we surface for audit.

## Backup plan
- **Network or LLM failure:** `DEMO_CACHE=only`. Scenes replay from recorded agent outputs, and the Trace Viewer says "cached".
- **Photon or phone failure:** in-app phone mirror panel.
- **Voice failure:** play the recorded call from the rehearsal.
- **Total failure:** the 3-minute backup video.
