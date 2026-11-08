# Decision room: research and product rationale

## Problem worth solving

Data center operators need to turn an observation into a safe, owned action. PitCrew already had field inspections, procedure checks, warnings and handover receipts. The missing entry point was a connected decision workspace that makes the next action and its evidence clear.

Sources reviewed November 8, 2026:

- [Uptime Institute, Annual Outage Analysis 2026](https://connect.uptimeinstitute.com/about-ui/press-releases/uptime-announces-annual-outage-analysis-report-2026): failure to follow established procedures remains the leading driver of human-error outages. This supports checking live prerequisites before maintenance and preserving an auditable work record.
- [Google SRE, Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/): excessive alerts obscure actionable problems; symptoms and proposed causes should be distinguished. This supports prioritizing commitments and showing evidence rather than adding a wall of measurements.
- [Google SRE, Monitoring](https://sre.google/workbook/monitoring/): useful metrics connect user impact with investigation and intended changes. This supports an explicit maintenance rehearsal that exposes consequences before the work begins.
- [NVIDIA Nemotron](https://www.nvidia.com/en-us/ai-data-science/foundation-models/nemotron/): open models support agentic applications. The repository's existing read-only tool workflow is an appropriate integration point; deterministic topology rules remain authoritative.

Product inference: a decision should carry its evidence, uncertainty, named owner, deadline, and next action into the next shift. This implementation demonstrates that workflow; it does not establish a measured reduction in outages or response time.

## What changed

The home page is now a Decision room. Existing technician work remains under My shift, rounds, procedures and handover.

1. A server-derived queue orders active warnings by severity, deadline and ownership. Resolved warnings are excluded. Ranking is deterministic and transparent, not an invented AI risk score.
2. Selecting a commitment shows its equipment trend, supplied evidence, field notes, assigned owner and missing read-back or fresh observation. The primary action opens the existing guided inspection.
3. Maintenance rehearsal evaluates an isolation against the current server snapshot. Before/after source availability exposes a loss of the final power path. The endpoint validates input and never mutates equipment or creates messages.
4. The result is invalidated when the clock or topology changes. Ordinary polling preserves it. It is a snapshot, not permission to execute work.
5. Handover and agent traces stay directly accessible.

The [Plane work-item reference on Mobbin](https://mobbin.com/screens/38bca3f2-f44e-4272-9fb9-714df6eb6edf) informed the relationship between a prominent task, ownership metadata and supporting history. It is a structural reference from project management, not a data-center-specific reference. The interface uses restrained green for evidence and amber for verification gaps, with responsive layouts and labeled controls. The topology visual is native UI rather than a generated asset so it can reflect equipment state.

## Technical boundaries

- `services/core/decisions.ts` derives the briefing and rehearsals from the existing typed PlantState and topology engine.
- `GET /api/decisions` returns the current brief. `POST /api/decisions` accepts a modeled power asset and isolation action. Existing API middleware protects both routes when server authentication is configured.
- Source reachability is not a capacity, protection-coordination, or electrical-independence study. The simplified seed topology cannot authorize a physical operation.
- The queue's evidence count is a count of records, not a confidence score. A missing fresh note is a prompt for field verification, not proof that an asset has failed.
- Existing Nemotron live/cached/fallback provenance is retained in Decision traces. Live NVIDIA inference was not verified in this work. No external messages or calls are needed for the demo.
- Demo state remains process-local under the existing demo persistence policy. Real BMS/DCIM telemetry, durable live deployment, identity, and account-side integrations require separate configuration and rehearsal.

## Next production validation

Validate feed independence and capacity against an actual facility model, calibrate queue priorities with operators, ingest timestamped BMS/DCIM measurements with freshness checks, and test whether shift receipts reduce missed follow-through. These are future validation steps, not implemented product claims.
