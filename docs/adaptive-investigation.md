# From acknowledgment to diagnosis

The core product now helps technicians decide what evidence to gather next. Typed read-backs remain available for handovers, but routine inspection ownership is a one-tap acceptance with an audit record. The app never invents text and presents it as the technician's own read-back.

## Ideas considered

| Idea | Value | Decision |
|---|---|---|
| Adaptive field investigation | Distinguish a physical problem from a misleading measurement; make each phone observation affect the next check | Implemented as the new main workflow |
| Maintenance conflict detection | Reveal a planned isolation removing the final modeled source | Existing rehearsal retained |
| Automatic shift memory | Preserve observations, current uncertainty and unfinished checks without retyping | Investigation results added to existing handover generation |
| Mandatory typed acknowledgment | Useful for selected critical communications, but burdens routine work | Removed from routine inspection ownership |

These are product hypotheses, not measured claims of reduced outages. The strongest demonstration is the closed loop between independent field evidence and the next diagnostic check.

## What is actually agentic

The diagnostic planner uses `nvidia/nemotron-3.5-lightning-30b-a3b` by default, configurable through `NEMOTRON_DIAGNOSTIC_MODEL`. The previous configured Nano endpoint returned HTTP 410 (retired); Super was listed but returned HTTP 404 for this account. Lightning successfully served the seeded tool-calling test on November 8, 2026.

Nemotron chooses from tools for trends, peer readings, notes, active work and procedures. It must successfully retrieve at least two distinct evidence tools before selecting a field check. After an independent reading agrees with telemetry, the model can choose either a physical check or a repeat measurement depending on the evidence. A disagreement requires verification before broader interpretation. A bounded final tool validates the selection against the available checks.

This is a bounded investigation agent, not a general autonomous operator. Rules preserve the independent measurements, determine qualitative support for the hypotheses, and constrain the available checks. The model explains its chosen next observation. Neither model nor rules operate equipment or close a warning automatically.

Live inference runs asynchronously. The response is applied only if the investigation ID and revision still match; a late response cannot overwrite a newer answer or a reset scenario. Missing credentials, timeouts, invalid results and provider errors produce a visibly labeled fallback.

The live rehearsal retrieved evidence over four turns and selected local reading → repeat reading → physical check → review. Inspect `tmp/decision-room/nemotron-live.json` after running the opt-in script to see actual model outputs and tool history. Do not portray deterministic mode as live AI.

## Phone demo

Open the public app at `/investigate/CH-3` after loading **S1**.

1. Leave **Use Nemotron** selected and start the investigation. The checkbox explains that demo evidence is sent to NVIDIA.
2. Wait for the live indicator. Inspect the evidence-tool history.
3. Enter **5.5** as the independent reading. The hypothetical local instrument agrees with telemetry.
4. Follow the selected next check. If it requests a repeat measurement, enter **5.5** again. For the physical check, choose **Something abnormal** and optionally enter **Rattle near pump B under load**.
5. At technical review, accept the follow-up with one tap. The warning remains open.
6. Open Handover and click **Draft from this shift**. The investigation's observations, uncertainty and next action appear without retyping.

For the contrasting story, load **S5** and open `/investigate/CRAH-1`. Enter **74**, then **74.1** on the repeat check, then **No abnormality observed**. This supports investigating the sensor/reference measurement rather than assuming equipment failure.

Uncheck Nemotron before starting for a reproducible offline presentation. The UI labels it **Evidence rules** and still demonstrates the two different branches. Loading another scenario resets all demo work.

## Validation and limits

Unit coverage includes branch selection, contradictory measurements, invalid answers, stale revisions, no telemetry mutation, no automatic warning closure, ownership acceptance, and handover propagation. Browser verification exercises both diagnostic paths and 320/390/1440-pixel layouts. Live model verification is opt-in: `node node_modules/tsx/dist/cli.mjs scripts/verify-investigation-live.ts` sends only the seeded S1 fixture to NVIDIA.

The comparison tolerance (5% of baseline, minimum 0.3 in the metric's unit) is a transparent demo heuristic, not a commissioned facility threshold. Measurements must represent the same metric and use an independent instrument. Two disagreeing readings do not prove sensor failure. Persistent storage follows the existing demo/live policy; demo records survive refresh but not server restart. Real facility deployment needs calibrated thresholds, identity, telemetry freshness and instrument provenance.

Research: [Uptime Institute's outage analysis](https://connect.uptimeinstitute.com/about-ui/press-releases/uptime-announces-annual-outage-analysis-report-2026) supports focusing on operational procedures and human error. [NVIDIA's AI factory operations work](https://developer.nvidia.com/blog/?p=124627) illustrates tool-based diagnostic agents. PitCrew's particular focus is connecting that investigation to evidence collected by a technician on the floor.
