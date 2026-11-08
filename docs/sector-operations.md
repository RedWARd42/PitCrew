# Sector operations

PitCrew is an operational response layer: investigate a developing issue with tools, dispatch qualified physical work, and preserve context when responsibility changes. It is not intended to replace Prometheus, Grafana, or a DCIM telemetry platform. The seeded vitals provide evidence for the demo; existing monitoring systems would supply signals in a production integration.

## Product decisions

Sector subscriptions express responsibility, not qualification. A technician also needs the right skill, equipment, access clearance, availability, and capacity. Location comes from an explicit sector check-in. It is a coarse proximity signal, not indoor GPS or a claimed walking-time estimate.

The dispatcher considers qualified subscribers first. If none are available, it escalates to a qualified on-call senior. An unanswered offer can time out; an accepted job is not silently reassigned just because time passed. If nobody is eligible, the case must remain visibly unassigned rather than being routed to an unqualified person.

“Response team” is a better description for the people than “technician fleet.” Technicians are not interchangeable. The demo has individual assignments and senior escalation; it does not pretend to optimize a real workforce or deploy multiple responders physically.

Each sector has three roles:

- Sentinel: evaluates telemetry and detects a changed condition. This is deterministic monitoring, not an LLM invocation for every sample.
- Investigator: retrieves evidence, checks context and shared memory, and produces a provisional diagnosis using Nemotron tools.
- Dispatcher: receives the investigator's case, inspects eligible responders, and proposes an assignment through a bounded tool call. The server enforces eligibility.

## Shared memory and observability

The shared memory is explicit, sector-scoped evidence and action history. It includes observations, diagnoses, technician work, and handoffs. It is not hidden model reasoning. Tool inputs and outputs are available separately in the activity record, with actor, timestamp, and execution mode.

Human field actions use the same operational record. Escalation carries completed steps, notes, unresolved work, and cautions forward. The incoming technician should see what has already been done and continue the remaining work.

Physical-work tickets are distinct from agent investigations. A telemetry discrepancy that can be checked digitally should not automatically page a person. Physical inspection and intervention require a qualified human. The demo does not let an agent operate plant controls.

## Demo boundaries

Facility telemetry, check-in location, personnel, access, equipment inventory, tickets, and notifications are simulated. Live Nemotron calls use that synthetic evidence. Notifications are delivered inside the app; no SMS or phone calls are sent.

State is shared within the running server process and survives browser refresh. It is not a durable production database, a multi-tenant authentication system, or a certified dispatch/safety system. Local browser persona selection demonstrates different roles; it does not authenticate a person.

Brev and MongoDB are intentionally not dependencies for this proof of concept. The already verified hosted NVIDIA endpoint provides the model execution needed for the demo. Brev could be evaluated later for self-hosted inference; MongoDB could persist case timelines and shared memory once the workflow warrants it.

## Success criteria

1. A developing sector fault triggers an investigation before a technician ticket appears.
2. Real model tool calls retrieve evidence and produce an auditable case.
3. An eligible sector responder receives the physical work; an ineligible closer person does not.
4. An agent-only telemetry check can end without creating a physical ticket.
5. An uncovered sector escalates to an eligible on-call senior.
6. A technician's observations and completed steps survive escalation and are shown to the next responder.

Research context: [Uptime Institute outage analysis](https://connect.uptimeinstitute.com/about-ui/press-releases/uptime-announces-annual-outage-analysis-report-2026) motivates reducing operational procedure failures. [NVIDIA's AI factory operations agents](https://developer.nvidia.com/blog/?p=124627) illustrate evidence-driven diagnostics through operational tools. The contribution demonstrated here is the connection between sector agents, skill-aware physical dispatch, and a continuous human/agent case record—not a claim that autonomous monitoring or ticketing is itself new.

## Five-minute demonstration

1. Open `/` on a laptop and `/tickets` on a phone. Keep the phone persona as Maria Santos; the laptop can use Dev Morgan. Both devices share the same synthetic facility state.
2. On the laptop, open **Demo controls**, keep **Live Nemotron** checked, and select **Cooling drift**. The investigator reads vitals, neighboring conditions, and sector memory, proposes a provisional diagnosis, and writes a shared case. The dispatcher reads that case and the eligible roster. Open **Activity** to inspect actual tool inputs and results; a live badge distinguishes model execution from rules.
3. On the phone, open the new work item and **Accept assignment**. The case already contains evidence, uncertainty, required tools, and field checks. Record one check with a specific observation, such as “Independent reading confirms 5.8°F; vibration persists.” This saves a technician action into the same sector history.
4. Open **Request senior support**, give the reason, and choose **Escalate with handoff**. On the laptop, switch to Dev Morgan and open the ticket. **Already done** includes Maria's finding; **Pick up here** contains only unfinished checks. Accept and continue. Completing the checklist closes the work item; it does not falsely claim the equipment repaired itself.
5. For a second short scenario, use **Sensor mismatch**. The redundant feed supports a simulated telemetry refresh and no field ticket is created. **No sector coverage** instead demonstrates the qualified on-call lead fallback. Loading a scenario resets the shared case, so finish the handoff demonstration first.

Monitoring is paused initially to keep the presentation predictable. **Start monitoring** advances the synthetic clock by 30 seconds every five real seconds; **Advance 60 seconds** demonstrates unattended-offer escalation. Accepted work is retained by its technician. New scenarios reset the demonstration; browser refresh does not.

The value is fewer unnecessary dispatches, a prepared first visit, and less repeated investigation after escalation. These are workflow outcomes demonstrated by the simulation, not measured production improvements in response time or uptime.

## Verified rehearsal

On November 8, 2026, the hosted `nvidia/nemotron-3.5-lightning-30b-a3b` endpoint completed the live seeded cooling case. The observed tool sequence was `read_sector_vitals`, `compare_neighboring_sectors`, `read_shared_memory`, `propose_diagnosis`, `write_shared_memory`, `read_case_brief`, `read_shared_memory`, `get_eligible_responders`, and `choose_dispatch`. Maria received the ticket. The phone-browser rehearsal accepted it, recorded an independent reading, escalated it to Dev, and accepted the handoff with one completed check and two remaining. No browser runtime errors or horizontal overflow were observed at 390 pixels.

Three focused backend tests cover handoff continuity and closure guards, uncovered/expired dispatch eligibility, and agent-only sensor handling with reset invalidation. This is demo verification, not a production reliability claim.

## Shift and preventive work

The current extension adds `/brief` and `/upkeep`. Shift patterns vary by facility; the demo does not assume a universal 12-hour rotation. The brief assembles urgent carryover, accepted work, completed checks, remaining observations, blocked plans, and sector coverage. Reviewing it records a snapshot, not a transfer of responsibility. Meaningful work or coverage changes mark a prior review as outdated; ordinary clock ticks do not.

The work queue highlights one next action and orders remaining assigned work by critical priority, accepted-work continuity, due date, then seeded sector proximity. It does not estimate walking minutes or claim measured fatigue savings. An urgent competing assignment asks the technician to coordinate a safe handover rather than abandon active work.

Upcoming work contains dated, synthetic inspection plans. A planner checks prerequisites, a two-hour lookahead to the completion deadline, and the approved work window. When work is ready, Nemotron retrieves `read_maintenance_plan`, telemetry, and shared memory, then prepares bounded physical checks and proposes an eligible responder. The server rechecks conditions before issuing work and on acceptance/field checks. A plan that overlaps an existing visit links to that case; closing an unrelated reactive visit does not silently complete the scheduled inspection.

The retirement example is a readiness inspection only. An available on-call lead with sector access records prerequisite evidence; the resulting hardware task verifies identifiers and visually documents labels. It never disconnects, erases, removes, or retires equipment.

### Additional demonstration

1. Open **Upcoming work** and choose **Review upcoming work**, or use **Demo controls → Preventive work** to start a fresh scenario.
2. The pump inspection is ready before its completion deadline. Rack readiness stays blocked by an unresolved service-owner prerequisite. The UPS inspection remains scheduled for its later window.
3. As Maria, use **Work queue → Review assignment**. Accept and record one check. **Shift brief** shows the current owner, completed work, and the next unfinished check; expand details for the findings.
4. Choose **Mark this brief reviewed**. Add a field note to the ticket, then return to see the review marked outdated. This prevents an old acknowledgement from making a changed brief appear current.
5. Switch to Dev on **Upcoming work**, record a specific synthetic service-owner/inventory verification in the prerequisite field, and submit it. A hardware readiness task routes to Sam. Future-window work remains unpaged.

Verification used one real Nemotron preventive case, a phone-browser rehearsal, and five focused backend tests (the existing three plus two upkeep checks). The model invoked `read_maintenance_plan` and completed the investigator/shared-memory/dispatcher sequence. Screenshots and live fixtures are private demo artifacts in `tmp/fleet-demo`.

Research: [Google's hardware operations role](https://www.google.com/about/careers/applications/jobs/results/90980510792065734-data-center-technician-global-server-operations-server-ops-hardware-operations?hl=en_US&jlo=en_US&page=8&q=&sort_by=date) includes preventative hardware maintenance and nonstandard shifts. [Uptime Institute's operations criteria](https://uptimeinstitute.com/professional-services/management-operations/mando-criteria) emphasize staffing, planning, coordination, and scripted maintenance procedures. These support the workflows; they do not establish a universal shift schedule or quantify walking-distance benefits.
