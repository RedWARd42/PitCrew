# PitCrew demo: from signal to safe action

**Updated primary demo:** use the [adaptive investigation walkthrough](adaptive-investigation.md). Routine inspection ownership now uses **Take this follow-up**, without a typed read-back. The older walkthrough below describes the original inspection path.

Open http://127.0.0.1:3012. The demo uses simulated equipment and communications. No plant controls are connected.

## 1. Catch the quiet warning (90 seconds)

1. Open **Demo scenarios**, then **Scenario Director**. Load **S1 · The quiet warning**. Return to the home page.
2. The Decision room places Chiller 3 in the priority queue. Show the actual reading against its baseline, the field note, the next action, and the missing owner read-back.
3. Click **Start field verification**. Review the evidence, save a reading of **5.6**, and add: “Pump B is rattling louder than yesterday. Check bearing this shift.”
4. Confirm ownership with: “I will inspect pump B bearing by 02:30.” Review and record the inspection.
5. Return to the Decision room. The warning remains open, but ownership is accepted. Explain that completing an inspection is not the same as resolving a fault.

## 2. Prevent the maintenance trap (60 seconds)

1. In Scenario Director, load **S2 · Before the breaker** and return home.
2. Select **Maintenance rehearsal**. Keep **PDU 4 · Breaker B** selected and click **Run rehearsal**.
3. Show **HOLD · Last source at risk** and **Row-D: N → LOST**. UPS-2 is already in bypass; isolating PDU-4 removes the remaining modeled path.
4. Explain that no equipment changed. The calculation ran server-side against the current topology. Open the approved procedure to see the existing maintenance guardian.

## 3. Keep the context across shifts (60 seconds)

1. Reload S1, finish the ownership step if desired, and open **Handover**.
2. Draft the outgoing brief using the existing handover controls. Review the next action and contingency attached to each item.
3. Confirm a read-back to demonstrate that receiving information is recorded separately from merely displaying it.
4. Open **Decision traces** to show supplied evidence, tool calls, and explicit deterministic/live/fallback provenance.

Pitch: “PitCrew closes the gap between seeing a warning and making sure the right person takes the next safe action. It connects field evidence, maintenance consequences, and shift ownership.”

## Start locally

Normal setup: `pnpm install`, then `pnpm demo` (default port 3000).

If dependencies are already installed but the pnpm registry launcher is unavailable, run from the repository root in PowerShell:

```powershell
$env:NEXT_DIST_DIR='.next-dev'
$env:DIRECTOR_TOKEN=''
$env:DEMO_MODE='1'
$env:DEMO_CACHE='only'
$env:COMMS_MODE='terminal'
$env:VOICE_MODE='simulated'
node apps/field/node_modules/next/dist/bin/next dev apps/field --hostname 127.0.0.1 --port 3012
```

Do not claim live Nemotron, SMS, voice, real telemetry, or measured outage prevention unless those integrations are independently configured and tested. All demo scenarios reset the seeded state, so finish one story before loading the next.
