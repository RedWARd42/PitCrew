# Task-led field experience

Branch `codex/task-led-field-experience` builds on the monochrome checkpoint `dc528a5` on `master`. The black/ghost-white identity, vector logo, background geometry, motion preferences, and existing safety checks remain. The product starts with an action rather than an overview of counts.

## The shift journey

1. **Start my shift** (`/start`): receive the inherited handover and record a read-back for each action. When all are confirmed the server records one `handover.received` receipt. The receipt survives drafting the outgoing brief, and its original read-backs remain inspectable on this screen.
2. **Work my rounds** (`/rounds`): one recommended next inspection and an ordered walking route. Priority comes from the existing risk engine. Reading a stop's context or opening its record alone never marks it complete.
3. **Guided inspection** (`/inspect/{assetId}`): review the evidence, record the observed reading, add an observation (including an explicit no-new-findings option), confirm ownership for open warnings, then review and record the inspection. Saved readings and notes can be resumed after reloading.
4. **Hand over my shift** (`/handover`): draft the outgoing I-PASS brief from current observations, ongoing warnings, maintenance, and unfinished procedures. Receiver confirmations and simulated delivery status keep their existing behavior.

The home page (`/`) puts incoming context, the next inspection, and active commitments in that order. Urgent incidents and existing procedure HOLDs surface as direct work links. There are no KPI summary cards. Equipment, procedures, team messages, tags, and power context remain supporting workspaces.

## Completion means a recorded inspection

`POST /api/command` accepts `{ "type": "complete_inspection", "assetId": "CH-3" }`. It succeeds only when:

- an asset reading was saved after its previous inspection completion;
- an observation was saved after that reading;
- every unresolved warning for that asset is owned and has a nonempty read-back.

Audit-array order is used because the simulated clock can be paused. The server appends `inspection.completed` to the existing audit collection and persists the normal state snapshot. Duplicate completion requires a fresh reading and observation. Rejections roll the state back and return 409. No new database schema or State field is needed.

Recording a visit never resolves a warning, closes a work order, completes a maintenance procedure, or operates equipment. The next recommended stop advances; open commitments stay visible and feed the outgoing handover.

## Presenter tools

Enter `/presenter` directly for the Scenario Director, full decision traces, message mirror, and equipment tags. Director and trace links are removed from technician navigation. These are separate UI workspaces under the existing server authentication, not a new role-based security boundary.

## Design references

Inspected [ClickUp task detail](https://mobbin.com/screens/52b2f142-aed2-4e12-9259-b6f99eda2dd9) and [Trello task detail](https://mobbin.com/screens/34353285-cb9a-4e8a-9746-83341f077283) informed a focused task body/checklist with adjacent context. [Lemonade Insurance on iOS](https://mobbin.com/screens/c139aea7-ddd1-41e4-aa87-dd3569d9d7d9) supplied an example of one decision followed by one next action. These products lend structure only; the field workflow, copy, palette, and state transitions belong to PitCrew. The inspection-category search returned weak matches, so checklist/task-detail references were used rather than claiming a maintenance-specific precedent.

## Verification

`scripts/verify-task-flow.ts` exercises a separate in-memory plant through the real frontend, with browser request interception and simulated transport. It checks three viewport widths, intake read-backs, all inspection steps, reload persistence, next-stop routing, retained warning ownership, presenter access, light/reduced motion, and the original S2 HOLD. Captures and its JSON report go to ignored `tmp/task-flow/`. `tests/e2e/field.spec.ts` exercises the built app's real HTTP API and browser flow in isolated demo mode. Focused unit tests cover completion guards and the durable incoming-handover receipt.
