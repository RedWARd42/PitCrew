# Groundtruth: Build Plan for Coding Agents

> **Working name:** Groundtruth (rename freely).
> **One-liner:** An AI ops partner that lives *at the equipment*. It turns the rounds, maintenance and shift changes data center technicians already do into an early-warning system. It reaches everyone off the floor by iMessage, SMS and phone calls.
>
> **Hackathon tracks targeted:**
> 1. **NMC² "Keep the World Running"** (primary)
> 2. **NVIDIA "Use Nemotron Beyond a Chatbot"**
> 3. **Photon "Best Use of Photon API"**, including the **Voice Call** prize

---

## 0. Instructions for the coding agent (read first)

You are the **lead engineer** on a hackathon build. Work **agentically and in parallel**:

1. **Read this entire document before writing code.** Then read the external docs listed in §14 for anything you integrate. Verify every model ID, package name and API shape against the live docs. They change often, and the names in this plan may be out of date.
2. **Contracts first (Phase 0).** Before spawning parallel work, write the shared contracts:
   - DB schema
   - API (OpenAPI)
   - Event types
   - Agent tool signatures
   - Seed-data format

   Commit them. Every workstream builds against these contracts and against mocks, never against another workstream's half-finished code.
3. **Then fan out.** Run the workstreams in §11 in parallel (subagents and/or `git worktree`s, one branch per workstream). Each workstream owns its directories and must not edit another's without a contract change.
4. **Integrate early and continuously.** A thin end-to-end slice should work by the end of Phase 1: simulator → backend → one agent → app screen → one iMessage. Then deepen.
5. **The demo is the product.** Everything must run in a **deterministic, seeded demo mode** (§12). That mode must replay the same scenario every time, keep working if the network is flaky, and fail gracefully.
6. **Quality bar:**
   - Typed code (TypeScript strict, zod validation at every boundary).
   - Unit tests for every deterministic engine.
   - Golden-scenario evals for every agent.
   - No secrets in the repo.
   - A README that a judge could follow.
7. **Frontend:** use any available frontend/design skills (for example an `apple-design` or `frontend-design` skill) and the **Mobbin MCP** to pull real reference screens before designing (§9). Ask the human if a skill or MCP isn't available.
8. **Stop and ask the human** before anything that costs money, needs an account or credentials, or changes scope. §15 lists what the human must provide.
9. **Decisions already made by the human (do not revisit):**
   - **One language: TypeScript everywhere.** The frontend, Photon SDK (`spectrum-ts`), agents, simulator and backend are all TypeScript. Agents use the **Vercel AI SDK**.
   - **Inference: hosted build.nvidia.com first.** Nobody downloads models locally. Brev self-hosting is an optional later phase (§10).
   - **Database: an existing Supabase project** (§4.2). Do not create a new one.
   - **Physical props come later.** Until then, test QR flows by scanning codes shown on a second screen.

---

## 1. Why this product: the research in one page

Two deep-research reports back this plan (*Data center uptime failure modes*, *Data center team challenges*). The key findings that drive the design:

| Finding | Design implication |
|---|---|
| Warnings existed before most major outages but nobody owned them. Heathrow's failed transformer showed bad oil test results 7 years earlier. CME's chiller problems were known ~16 hours before markets halted. Optus missed a rising failure rate at 2:40 a.m. | Every anomaly becomes an **owned warning** with an assignee, a deadline and automatic escalation. |
| ~59% of human-error outages involve procedures not followed, and ~36% involve incorrect procedures (Uptime Institute 2026). | **Procedure Guardian**: each maintenance-procedure step is checked against the live plant before it's done. |
| Many outages start during maintenance or changes while redundancy is quietly reduced (Equinix SG1, the Korea NIRS fire, OVH). Changes are involved in 45–64% of network/IT outages. | The **redundancy state** is a first-class, always-visible concept. Every step and alarm is aware of it. |
| Handoffs fail mostly *between organizations*: colocation provider ↔ tenant, vendor ↔ operator, contractor ↔ owner. | Photon reaches people who won't install an app (on-call engineers, vendors, tenants) on iMessage, SMS or a voice call. |
| Hospital structured handoffs (I-PASS) cut medical errors 23% and preventable adverse events 30%. Aviation uses read-back (closed-loop) communication. | **Walk-through handover** in I-PASS format with **read-back acknowledgement**. |
| Alarm floods: one chiller trip produced 47 alarms in 90 seconds. ISA-18.2 treats more than 10 alarms in 10 minutes as a flood. | Alarms are **correlated into one incident** by cause and topology. |
| Precursor lead times vary by asset: VRLA battery impedance rises over 2–4 weeks, transformer gas analysis gives months, GPUs give days of memory-row remaps, Li-ion off-gas gives 5–20 minutes, liquid-cooled racks give seconds. | **Per-asset baselines and drift detection**, plus a **time-to-threshold** projection. |
| About 1 in 4 critical sensors are inaccurate. | **Sensor sanity checks** against neighbors and physics before raising anything. |
| Only 16% of operators are comfortable with AI making automated changes, but 71% trust AI for analytics. | **Advisory-only agents.** Show reasoning. A human approves. Agents never write to plant controls. |
| No data center shift-handover product exists. The closest competitor is Phaidra Prism, a read-only Q&A assistant for the control room. | Differentiator: we manage the **work around the equipment** for the **technician on the floor**. |

**Design principle: no dashboards.** Every screen is about **an asset, a task, or a person**. There are no wall-of-charts screens anywhere.

---

## 2. Users and core story

**Personas**
- **Maria, floor technician (night shift).** Gloves on, phone or rugged tablet, doing rounds and maintenance. Primary user of the field app.
- **Dev, on-call chief engineer (at home).** Reached by iMessage, SMS or phone call. Never opens the app unless he wants to.
- **Sam, vendor field engineer (e.g. the chiller OEM).** Added to incident group chats on WhatsApp or SMS.
- **Priya, tenant ops contact.** Receives customer-facing incident updates. Her decisions (such as whether to fail over) depend on accurate time-to-impact information.

**Core loop:** Sense → Understand → Own → Act → Hand over.
This follows **Endsley's three levels of situational awareness**: Perceive, Comprehend, Project. It adds ownership and handover rituals from aviation and medicine.

---

## 3. Feature spec

Priority key: **P0** = must ship for the demo, **P1** = should ship, **P2** = stretch.

### 3.1 Field app (mobile-first PWA)

| # | Feature | Priority | Acceptance criteria |
|---|---|---|---|
| F1 | **Tap-to-asset** | P0 | Scanning a QR code (or tapping an NFC tag that holds a URL) opens `/a/{assetId}`. The asset page shows: live status, redundancy context ("UPS-2: **in bypass**, Row 4 on single feed"), open warnings, pinned notes, last 3 shifts' history, related procedures. It loads in under 1 s on Wi-Fi. |
| F2 | **Smart rounds** | P0 | A round is an ordered list of stops. The order is **re-ranked by risk** each shift and the app explains why: "Chiller 3 first: drift + open note". At each stop the tech enters a reading by keypad, voice, or (P2) a gauge photo. The reading is compared instantly to that asset's own baseline. If it's off, an inline chip appears: "↑ 1.5°F vs 5-day baseline". |
| F3 | **Pinned notes** | P0 | Text or voice notes attach to an asset. Voice is transcribed, then structured by the agent into {component, symptom, severity, follow-up}. Notes appear for the next person who opens the asset and in the handover. |
| F4 | **Owned warnings** | P0 | A warning has an owner, a severity, a deadline, an evidence pack, and an escalation ladder. Owners accept with a read-back: "I'll check pump B bearing by 02:30". The UI makes **who owns it** and **time left** obvious. |
| F5 | **Procedure Guardian** | P0 | Open the procedure for an asset and step through it. Before each step, the agent shows **GO** or **HOLD** with its reasoning, computed against the live plant. Example: "Step 6 opens breaker B. UPS-2 is in bypass, so this drops Row 4. HOLD." A HOLD requires an explicit override with a reason, and the override is logged. |
| F6 | **Walk-through handover** | P0 | At shift end the agent drafts an I-PASS handover. The items are **ordered by walking route**, each linked to its asset. The incoming tech confirms each critical item, and unconfirmed items stay highlighted. |
| F7 | **Redundancy meter** | P1 | A persistent, compact header pill shows the site's current redundancy state (e.g. "Hall 2 power: N+1 → **N**"). Tapping it opens a small topology view showing what's degraded and why. This is the only "map-like" view; it is not a dashboard. |
| F8 | **Time-to-limit** | P1 | During active incidents, a countdown: "≈14 min until CHW supply exceeds the chiller restart limit (62°F)". It shows the confidence band and the assumptions used. |
| F9 | **Incident mode** | P1 | When alarms correlate into an incident, the app switches to a focused incident card. It shows: one root-cause hypothesis, affected assets, the owner, time-to-limit, the right emergency procedure (EOP), and who has been contacted (iMessage, call, group chat). |
| F10 | **AR mode** | P2 | Marker-based AR (MindAR image targets, or the QR code itself as the target). Pointing the camera at the equipment photo/marker floats labels over it: drift, open notes, HOLD. Clearly optional, because many facilities restrict cameras. |
| F11 | **Gauge/nameplate photo → reading** | P2 | A vision model reads an analog gauge or nameplate photo into a structured reading. Must have a fallback if the camera is disallowed. |

### 3.2 Agents (Nemotron), detailed in §6

| # | Agent | Priority |
|---|---|---|
| A1 | **Procedure Compiler**: turns a PDF method of procedure (MOP) into structured steps with machine-checkable preconditions | P0 |
| A2 | **Procedure Guardian**: per-step GO/HOLD against live state | P0 |
| A3 | **Investigator**: triggered by a drift or alarm; plans and runs a multi-step investigation and produces an owned warning | P0 |
| A4 | **Incident Coordinator**: correlates the alarm flood into one incident; runs the escalation ladder across channels | P1 |
| A5 | **Field Scribe**: voice/photo note → structured entry | P0 (voice), P2 (photo) |
| A6 | **Handover Writer**: drafts the I-PASS handover and tracks confirmations | P0 |
| A7 | **Plant Q&A over chat and voice**: answers "what's UPS-2's status and who owns it?" with tools | P1 |

### 3.3 Photon communications, detailed in §7

| # | Feature | Priority |
|---|---|---|
| P1 | Escalation DM with an **app card** (trend, redundancy, buttons) and an ACK via reply or poll | P0 |
| P2 | Escalation ladder: DM → wait → next person → **automated outbound voice call** | P0 (DM), P1 (call) |
| P3 | **Incident group chat**, auto-created, named and avatar'd, with members added by role (tech, chief, vendor, tenant) and live updates edited in place | P1 |
| P4 | Inbound plant Q&A by text and by **voice call** | P1 |
| P5 | Handover summary sent to the incoming shift's phone before they arrive, with per-item confirmation | P1 |

### 3.4 Presenter-only tools (not product UI)

| # | Feature | Priority |
|---|---|---|
| D1 | **Demo Director**: a hidden page/CLI to start scenarios, step the clock, inject faults, reset, toggle "offline cache" mode | P0 |
| D2 | **Agent Trace Viewer**: shows the agent's plan, tool calls, and reasoning trace for any decision. Judges for the NVIDIA track will want to see this. Make it beautiful and readable, not a log dump. | P0 |

### Explicit non-goals
- No wall dashboards.
- No autonomous control of plant equipment.
- No real BMS/BACnet integration. We simulate it, but the adapters are designed to be swapped for real ones (§5.4).

---

## 4. Architecture

```
                         ┌───────────────────────────────────────────┐
                         │                 Field App                 │
                         │  Next.js PWA (mobile-first) + MindAR (P2) │
                         └──────────────┬────────────────────────────┘
                                        │ REST + Supabase Realtime/SSE
┌───────────────┐  telemetry/events ┌───▼───────────────────────────┐   tools (MCP/HTTP)  ┌───────────────────────┐
│ Plant         ├──────────────────►│ Core API (Node/TS, Hono)      │◄───────────────────►│ Agent Service (TS,    │
│ Simulator     │                   │ - Postgres (Supabase)         │                     │  Vercel AI SDK)       │
│ (TypeScript)  │◄──────────────────┤ - Deterministic engines:      │  events (queue)     │ - Nemotron via        │
│ - topology    │  fault injection  │   drift, sanity, redundancy,  ├────────────────────►│   API (NIM/vLLM)      │
│ - physics-ish │                   │   correlation, time-to-limit  │                     │ - planner/executor    │
│ - scenarios   │                   │ - event bus, audit log        │                     │ - trace store         │
└───────────────┘                   └───┬───────────────────────────┘                     └──────────┬────────────┘
                                        │ notify/escalate events                                    │
                                ┌───────▼──────────────────────┐                                    │
                                │ Comms Service (TypeScript)   │◄───────────────────────────────────┘
                                │ - Photon Spectrum (iMessage, │   (agents call notify/escalate tools)
                                │   SMS/RCS, WhatsApp)         │
                                │ - Voice bridge: LiveKit/SIP  │
                                │   ↔ Photon voice line        │
                                └──────────────────────────────┘
```

**Key architectural rule:** **LLMs orchestrate and explain; deterministic code computes.**
- Redundancy impact, drift statistics, sensor sanity checks, alarm correlation and time-to-limit are **plain, tested code**.
- Agents call those engines as tools and reason over the results.
- Say this explicitly in the pitch. It answers "can we trust an LLM near critical infrastructure?"

### 4.1 Tech stack (decided: all TypeScript)
- **Monorepo:** pnpm workspaces + Turborepo. TypeScript `strict` everywhere. **zod** is the single source of truth for schemas: DB row types, API payloads, agent tool inputs/outputs, and agent final outputs.
- **Frontend:** Next.js (App Router) + Tailwind + Framer Motion. PWA manifest. Use shadcn/ui primitives only where they don't fight the iOS-native feel. Use `@supabase/supabase-js` for realtime subscriptions.
- **Core API:** Node 20+ with **Hono** (or Next.js route handlers if simpler; pick one and document it). Uses Supabase (Postgres) through `supabase-js` with the service key on the server only, or a direct Postgres client (Drizzle ORM) for migrations and complex queries. Supabase Storage holds audio and PDFs.
- **Agents:** **Vercel AI SDK** (`ai` + `@ai-sdk/openai-compatible`) pointed at Nemotron's OpenAI-compatible endpoint.
  - Multi-step tool loops: `generateText`/`streamText` with `tools` and a step limit (`stopWhen`). Check current AI SDK docs for exact API names.
  - Structured final outputs: `generateObject` / structured output with zod schemas.
  - Expose the tool registry over HTTP and as an **MCP server** (`@modelcontextprotocol/sdk`) so any harness, including the voice agent, can reuse it.
  - **Do not** build on NVIDIA NeMo Agent Toolkit. It was deprecated in October 2026 and reaches end of life at the end of 2026.
  - Do not use LangChain. LangGraph is acceptable only if the AI SDK can't express a needed pause/resume. The HOLD override is handled in our own state machine, so it shouldn't be needed.
- **Comms:** TypeScript service using `spectrum-ts` (Photon Spectrum).
  - Voice: a LiveKit Agents worker (Node SDK `@livekit/agents`, or ElevenLabs/Retell per Photon's voice cookbooks) connected over SIP to the Photon line. The LLM is Nemotron.
- **Simulator:** TypeScript (a seeded PRNG such as `seedrandom`). Emits readings at 1 Hz (configurable); the demo clock can be accelerated.
- **Testing:** vitest (unit), fast-check (property tests for the topology engine), Playwright (mobile-viewport smoke tests).
- **Infra:** Docker Compose for local services; the frontend can deploy to Vercel. For the optional self-hosted LLM, a **Brev** GPU instance runs vLLM or NIM (§10).

### 4.2 Supabase (already created; do not create another)
- **Project ref:** `hrkuvnanhchdvinviaii` · **URL:** `https://hrkuvnanhchdvinviaii.supabase.co` · Postgres 17 · us-east-1. Empty at handoff.
- **Security settings (verified):**
  - **Automatic RLS is ON.** An `ensure_rls` event trigger enables RLS on every new `public` table.
  - **"Automatically expose new tables" is OFF.** Tables created by migrations get **no** Data API read/write grants, *including for `service_role`*.
- **Therefore every migration that creates a table must:**
  1. `grant select, insert, update, delete on public.<table> to service_role;` (backend access through the Data API).
  2. Grant to `authenticated` / `anon` **only** for tables the frontend reads directly, and add RLS policies for them. Demo mode can use a simple "demo user" policy. Never expose writes to `anon`.
  3. `alter publication supabase_realtime add table public.<table>;` for tables the app subscribes to (warnings, incidents, notes, readings_latest, messages).
- Use the Supabase agent skill (`npx skills add supabase/agent-skills`), which includes the grants step, and/or the Supabase MCP. Keep migrations in `supabase/migrations` and use the Supabase CLI.
- **Keys:** the human puts the publishable/anon key and the secret/service key into `.env`. The service key is server-only, never committed and never sent to the browser.

### 4.3 Repo layout
```
groundtruth/
  apps/field/              # Next.js PWA (WS4)
  apps/director/           # Demo Director + Agent Trace Viewer (WS6) — can be routes inside apps/field under /_director
  services/core/           # Hono API, DB access, engines, REST, SSE (WS2 + WS1 engines)
  services/sim/            # Plant simulator + scenarios (WS1, TypeScript)
  services/agents/         # Nemotron agents (Vercel AI SDK), tool registry, MCP server, evals (WS3)
  supabase/migrations/     # SQL migrations incl. GRANTs + realtime publication (WS2)
  services/comms/          # Photon Spectrum + voice bridge (WS5)
  packages/contracts/      # zod schemas → OpenAPI, event types, tool schemas, TS types (WS0)
  data/                    # seed site, procedures (PDF + compiled JSON), scenarios, demo cache
  docs/                    # README, architecture, demo script, judging map
  turbo.json, pnpm-workspace.yaml, docker-compose.yml
  .env.example
```

---

## 5. Domain model and simulation

### 5.1 Core entities (Postgres)
- `site`, `zone` (hall, row), `asset` (id, type, name, zone, tag_url, vendor, criticality, parent/feeds relationships)
- `topology_edge` (from_asset, to_asset, kind: `power`|`cooling`|`network`, redundancy_group)
- `sensor` (id, asset_id, metric, unit, neighbors[], expected_range)
- `reading` (sensor_id, ts, value, source: `telemetry`|`round`|`photo`). Use a time-indexed table; downsample for the UI.
- `baseline` (sensor_id, window, mean, std, slope, updated_at)
- `alarm` (id, asset_id, code, priority, ts, state, correlated_incident_id)
- `incident` (id, title, hypothesis, severity, state, owner_id, time_to_limit, created_at)
- `warning` (id, asset_id, title, evidence_json, severity, owner_id, due_at, state: `open`|`owned`|`escalated`|`resolved`, escalation_level, readback_text)
- `note` (id, asset_id, author_id, text, audio_url, structured_json, ts)
- `procedure` (id, title, asset_types[], source_pdf_url, compiled_json, version, approved_by)
- `procedure_run` (id, procedure_id, asset_id, tech_id, current_step, state) and `procedure_step_check` (run_id, step_no, verdict `GO`|`HOLD`, reasoning, inputs_snapshot, override_reason)
- `work_order` (id, asset_id, title, state, assignee, source_warning_id)
- `maintenance_window` (asset_id, starts, ends, redundancy_impact)
- `person` (id, name, role, phone, channel_prefs, on_call bool), `shift` (id, starts, ends, members[])
- `round` (id, shift_id, stops[] ordered, rationale_json), `round_stop` (asset_id, checks[], completed_at)
- `handover` (id, from_shift, to_shift, items_json, confirmations_json)
- `message_log` (channel, direction, person_id, content, related_entity, photon_message_id)
- `agent_trace` (id, agent, trigger, plan_json, steps_json[tool calls, results, reasoning], final_json, model, latency_ms)
- `audit_log` (everything a human or agent did)

### 5.2 Seed site: "NMC² DAL-1, Hall 2" (fictional)
**Power**
- Utility A/B → MV switchgear → 2× UPS (UPS-1, UPS-2) with battery strings (VRLA strings 1–4; one Li-ion cabinet).
- UPS → PDUs → Rows A–F. Row D is an AI row fed via busway.
- Generator GEN-1 with an ATS.
- Each row is dual-corded (A/B feeds). Row 4/D's A and B feed relationships let a breaker step drop it when the other side is in bypass.

**Cooling**
- 3 chillers (CH-1..3, N+1), chilled-water (CHW) pumps P-1..3, 6 CRAH units.
- 1 CDU (coolant distribution unit) for the liquid-cooled AI Row D (supply/return temperature, flow, pressure, glycol %).

**IT (light touch)**
- Row D GPU servers report coarse telemetry: power, inlet temperature, ECC/row-remap counters for one "repeat-offender" node.

**People**
- 4 techs on 2 shifts, 1 on-call chief, 1 vendor contact, 1 tenant contact.
- Use the team's real phones for the demo people (§15).

**Procedures (MOPs/EOPs), 4–6 PDFs**
- "UPS-2 maintenance bypass & PDU-4 isolation"
- "CHW pump swap"
- "Chiller restart after trip" (with the restart temperature limit)
- "Battery string impedance test"
- "CDU filter change"

Write them as realistic, slightly messy PDFs: tables, a one-line diagram image, a note in the margin. That gives the vision model (Nemotron VL) real work to do. Also include one **outdated** procedure revision to demonstrate version checks.

### 5.3 Scenarios (scripted, seeded, replayable)
Each scenario is a YAML timeline of fault injections and expected agent outcomes, used both for the demo and for evals.

| ID | Scenario | What it demonstrates |
|---|---|---|
| S1 | **Slow chiller drift.** CH-3 approach temperature drifts +1.5°F over 5 simulated days; day shift logged a "rattle near pump B". | Smart rounds re-ranking, drift chip, Investigator → owned warning → iMessage escalation |
| S2 | **Maintenance trap.** UPS-2 placed in bypass for planned work; a tech runs a PDU procedure whose step 6 would drop Row D. | Procedure Guardian HOLD, redundancy meter |
| S3 | **Chiller trip cascade.** Voltage dip trips CH-1 and CH-2; standby CH-3 fails to auto-start; 40+ alarms in 90 s; CHW supply temperature rising toward the restart limit. | Alarm correlation → one incident, time-to-limit, EOP surfaced, escalation ladder → **voice call**, incident group chat with vendor and tenant. (Mirrors Azure Australia East 2023.) |
| S4 | **Battery string impedance creep.** VRLA string 3 cell impedance +15% over 3 weeks; voltage still normal. | Multi-horizon precursor, per-asset baseline beating fixed thresholds (quarterly checks would miss it) |
| S5 | **Lying sensor.** One CRAH return-air sensor reads 8°F high vs neighbors and the energy balance. | Sanity check suppresses a false alarm and creates a "calibrate sensor" work order instead |
| S6 | **GPU repeat offender** (P2). Correctable memory-row remaps climb on one node over days. | Days of warning; cross-domain IT↔facility context |

**Optional realism:** calibrate chiller fault signatures with the LBNL fault-detection datasets (simulated chiller plant with labeled faults). Cite that in the pitch. Not required for the MVP.

### 5.4 Adapter boundary (for the "real world" question)
Define a `TelemetrySource` interface: `subscribe(sensors) -> stream`, `snapshot(assets)`.
- The simulator implements it.
- Stubs show where BACnet/Modbus/SNMP/Redfish adapters would plug in.
- Mention Redfish's liquid-cooling schema (CoolantConnector) and Project Haystack/Brick tagging as the real integration path.

---

## 6. Agents (Nemotron, "beyond a chatbot")

### 6.1 How we satisfy the NVIDIA criteria

| NVIDIA criterion | How we meet it |
|---|---|
| **Beyond a chatbot** | Agents are triggered by **events** (drift, alarm, step-advance, shift end), not by a user prompt. The only chat surface (A7) is secondary. |
| **Multi-step workflows** | The Investigator and Incident Coordinator **plan** (an explicit, visible plan), then execute 4–10 tool calls, re-plan on new evidence, and produce a structured artifact. |
| **Tool integration** | Agents use ~15 tools: plant telemetry, topology/redundancy engine, CMMS, procedures, roster, the Photon messaging/voice APIs, and a vision model for documents and photos. |
| **Real-world applicability** | Every scenario mirrors a documented real outage (§1). Advisory-only, auditable, with an on-prem deployment path via self-hosted Nemotron. |

### 6.2 Model routing (verify exact IDs on build.nvidia.com at build time)
| Role | Model (preferred → fallback) | Why |
|---|---|---|
| Heavy reasoning: Investigator, Guardian, Incident Coordinator | `nvidia/nemotron-3-super-120b-a12b` → `nemotron-3-nano-30b-a3b` | Deeper multi-step reasoning and synthesis |
| High-volume workers: Field Scribe, round re-ranking rationale, handover drafting, chat Q&A | `nvidia/nemotron-3-nano-30b-a3b` or `nemotron-3.5-lightning-30b-a3b` | Fast, cheap, strong tool calling; self-hostable on one GPU |
| Watcher / async escalations (optional) | `nvidia/nemotron-3.5-bolt-e4b` | Compact, with an **asynchronous tool-calling** protocol, which suits long-running escalation timers |
| Documents and images: Procedure Compiler, gauge photos | `nvidia/nemotron-nano-12b-v2-vl` (or the current Nemotron VL/Omni) | Document understanding, OCR, charts |
| Embeddings for procedure/note retrieval (P1) | Current NVIDIA retriever embedding NIM on build.nvidia.com | Find the right procedure and past notes |

Implementation notes:
- One provider factory: `createOpenAICompatible({ name: "nvidia", baseURL: process.env.NEMOTRON_BASE_URL ?? "https://integrate.api.nvidia.com/v1", apiKey: process.env.NVIDIA_API_KEY })`. Per-agent model config lives in one TS/JSON file, so a model can move from hosted to Brev self-hosted by changing a base URL.
- Use **reasoning on** for the Guardian and Investigator. Nemotron's switch is `enable_thinking`, passed through the chat template. With the AI SDK, try `providerOptions` / extra request body (e.g. `chat_template_kwargs: { enable_thinking: true }`), and **verify against the model card and a live call**. Parse the reasoning from the response and store it in `agent_trace`. Show a cleaned "Why?" summary in the UI.
- **Rate limits:** the free hosted tier is roughly **40 requests/minute** (it depends on model and traffic), and it's for prototyping.
  - Put every LLM call behind one shared limiter/queue (e.g. `p-limit` or `bottleneck`, ~30 RPM). Retry 429s with backoff.
  - Use Nano for high-volume calls.
  - Cache aggressively in dev and demo mode (§12).
  - Evals and parallel coding agents can burn the quota fast. Run evals against the cache by default (`EVAL_LIVE=1` to hit the API).
- Use **structured outputs / JSON schema** for every agent's final output. Validate with zod and retry once on a schema failure.
- Follow the model card's recommended sampling settings (for example, the Nemotron 3 Super card recommends `temperature=1.0, top_p=0.95`). In demo mode, use seeds and cache responses (§12).
- Timeouts plus a graceful fallback: if the LLM fails, the deterministic engine result is still shown with a templated explanation. The demo must never hang.

### 6.3 Tool registry (shared by all agents; also exposed via MCP)
```
get_asset(asset_id) -> Asset + status + open items
get_live_state(asset_ids[]) -> latest readings, states (bypass, running, tripped)
get_trend(sensor_id, window) -> series + baseline + drift stats (engine)
compare_siblings(asset_id, metric) -> how this unit compares to its N+1 siblings
check_sensor_sanity(sensor_id) -> agrees_with_neighbors, energy_balance_ok, confidence (engine)
get_topology(asset_id, depth) -> upstream/downstream power & cooling graph
simulate_action(action) -> redundancy impact: which loads lose a source, resulting N-level (engine)  ← core of Guardian
get_active_work(asset_ids[]) -> maintenance windows, open work orders, procedure runs in progress
project_time_to_limit(sensor_id, limit) -> eta_minutes, confidence band, assumptions (engine)
correlate_alarms(window) -> clusters with candidate root causes (engine)
search_procedures(query | asset_type) -> ranked procedures (+ version/approval status)
get_notes(asset_id, since) / add_note(...)
get_roster(now) -> who's on shift, on-call, skills, contact prefs
create_warning(...) / assign_owner(...) / set_deadline(...)
create_work_order(...)
notify(person_id, message, card?) -> via comms service (Photon)
start_escalation(warning_id, ladder) -> comms service runs timers; emits ack/timeout events
open_incident_chat(incident_id, roles[]) -> Photon group
place_call(person_id, briefing) -> voice bridge
```

### 6.4 Agent specs

**A1. Procedure Compiler** (offline / on upload)
- **Input:** a method-of-procedure PDF (MOP).
- **Process:** VL model extracts the steps, tables and the one-line diagram labels. A reasoning model then turns each step into:
  `{step_no, text, action:{type, target_asset}, preconditions:[machine-checkable predicates], hazards, verification}`.
  Example predicate: `state(UPS-2) != "bypass"` OR `alt_feed_ok(Row-D)`.
- **Output:** compiled JSON, stored with version and source hash. The human reviews and approves it in a small diff UI (P1).
- **Eval:** compiled steps match hand-written expected JSON for the 4–6 seed MOPs (step count, targets, predicates).

**A2. Procedure Guardian** (on each step-advance)
- **Plan:** read step → `get_live_state` → `get_active_work` → `simulate_action(step.action)` → evaluate preconditions → verdict.
- **Output:** `{verdict: GO|HOLD, reasoning_summary, evidence[], suggested_safe_alternative?}`. HOLD needs a human override reason.
- **Eval:** S2 must produce HOLD with the reason "Row D loses its last source". The same step with UPS-2 online must produce GO. No false HOLDs on 20 benign steps.

**A3. Investigator** (on drift or a non-trivial alarm)
- **Visible plan** (rendered in the Trace Viewer as a checklist that ticks off live):
  1. `get_trend` + `check_sensor_sanity` (is this real?)
  2. `compare_siblings` (unit-specific or plant-wide?)
  3. `get_active_work` + `get_notes` (recent maintenance? human observations?)
  4. `project_time_to_limit` (how urgent?)
  5. `search_procedures` (what should be done?)
  6. `get_roster` → choose an owner by skill and shift
  7. `create_warning` + `start_escalation`
- **Output:** a warning with a hypothesis, a confidence level, an evidence pack (charts as data, not images), a next action, a deadline and an owner.
- **Eval:**
  - S1 → owner is the on-shift mechanical tech, due within the shift, cites the rattle note and sibling comparison.
  - S5 → *no* warning; instead a calibration work order.
  - S4 → warning with a weeks-scale deadline.

**A4. Incident Coordinator** (when `correlate_alarms` finds a cluster above severity X)
- Collapses the alarm flood into one incident with a root-cause hypothesis ("voltage dip → CH-1/CH-2 trip; CH-3 failed to auto-start").
- Runs `project_time_to_limit`, surfaces the matching EOP, assigns an incident owner, and starts the escalation ladder:
  1. on-shift lead (app)
  2. on-call chief (iMessage card) → **voice call** after N minutes with no ACK
  3. vendor + tenant (group chat)
- Posts updates as the situation evolves, editing the pinned status message rather than spamming.
- **Eval (S3):**
  - 40+ alarms → 1 incident with the correct root-cause candidate in the top 2.
  - Time-to-limit within ±20% of the simulator's ground truth.
  - The escalation ladder fires in order.

**A5. Field Scribe:** voice transcription (any good ASR: NVIDIA Riva/Parakeet NIM if available, otherwise Whisper or a hosted STT) → Nemotron Nano → `{asset_component, symptom, severity, needs_follow_up, suggested_check}`. Low latency. Runs on every note.

**A6. Handover Writer:** at shift end, gathers open warnings, incidents, notes, overrides, maintenance windows and unfinished rounds.
- Writes an **I-PASS** handover:
  - **I**llness severity → site risk level
  - **P**atient summary → asset situation
  - **A**ction list
  - **S**ituation awareness & contingency
  - **S**ynthesis by receiver → read-back
- Orders items by the incoming tech's route. Each critical item needs a confirmation in the app or by an iMessage reply.

**A7. Plant Q&A** (text or voice): a tool-using agent over the same registry, read-only plus `add_note` and `create_work_order`. Must cite the data it used.

### 6.5 Guardrails
- Agents **cannot** write to plant state. Only notes, warnings, work orders, notifications, and HOLD verdicts.
- Every agent output is stored with inputs, tool calls, model and latency (`agent_trace`) and is reviewable.
- Do not send PII or plant details beyond what is needed over consumer channels. Send summaries plus deep links (§7.4).

---

## 7. Photon integration (messaging + voice)

> Read Photon's docs index first: https://photon.codes/docs/llms.txt
> Photon has two doc versions: **Stable (Spectrum, `spectrum-ts`)** and **Beta 2.0 (Photon platform, with Python client, voice-agent guide and voice cookbooks)**. The docs say to pick one per project.
>
> **Default:** use **Stable Spectrum** for messaging (it has app cards, polls, groups, renaming, membership and read receipts). Implement voice per the Spectrum Voice SIP docs (outbound calls via `sip.spectrum.photon.codes`, **TCP transport only**, iMessage lines only). Use the Beta voice cookbooks (LiveKit / ElevenLabs / Retell) as reference for wiring a voice agent.
>
> If the two versions conflict, **ask the human to confirm with Photon mentors** at the hackathon. Sign-up: https://app.photon.codes (promo code provided to the team).

### 7.1 Messaging features to use (and why judges will care)
| Photon capability | Our use |
|---|---|
| DMs on iMessage with SMS/RCS fallback | Escalation to the on-call chief; handover to the incoming shift |
| **App cards** (`app` content, updatable) | The warning/incident card: mini trend, redundancy state, owner, time-to-limit, buttons (Own / Need help / Dispatch vendor / Open in app). **Update the same card** as the situation changes. |
| **Polls** | One-tap ACK / choose action when buttons aren't available |
| Replies / threading | Read-back: "Reply with your next action" |
| **Read receipts** (inbound) | "Read but not acknowledged" is a distinct escalation state, shown in the app |
| Typing indicators | Show the agent is working while it investigates |
| **Groups: create, rename, avatar, membership** | Auto-create "INC-0042 · Hall 2 cooling"; add the vendor and tenant; set the avatar to the severity color |
| Edits | Keep a single living status message instead of spamming |
| Voice notes (content) | Agent sends a 15-second spoken briefing into the chat (P2) |
| WhatsApp Business / Telegram providers | Vendor or tenant on WhatsApp: same code, different provider |
| **Terminal provider** | Local development and CI testing without phones |

### 7.2 Escalation ladder (state machine in the comms service)
```
OPEN → notify(owner, card) ─┬─ ACK (reply/poll/button/app) → OWNED (store read-back text)
                            ├─ READ, no ACK after T1 → nudge + mark "read, unacknowledged"
                            └─ no ACK after T2 → notify(next on ladder) + place_call(on-call)
CALL → voice agent briefs, asks for verbal ACK ("say 'I own it'") → OWNED or escalate further
```
Timers are compressed in demo mode (T1 = 20 s, T2 = 45 s). Every transition is written to `audit_log` and shown in the app.

### 7.3 Voice (aim for the Voice Call prize)
- **Outbound "wake-up call":** when the ladder reaches CALL, a voice agent phones the on-call chief through the Photon line.
  - It gives a 20-second structured briefing: what, where, how bad, time-to-limit, what's been done.
  - It answers follow-up questions using the **same tool registry** ("is the vendor engaged?", "what's the redundancy now?").
  - It captures a **verbal read-back** ACK and writes it back to the warning or incident.
- **Inbound "call the plant":** a tech or engineer calls the line and asks, "What's open on Chiller 3?" or "Log a note: pump B still rattling." The voice agent uses A7 tools.
- **Implementation:**
  - A LiveKit Agents worker (or ElevenLabs/Retell per the Photon cookbooks) connected over SIP to the Photon line.
  - LLM = Nemotron via an OpenAI-compatible endpoint, with the same tool registry.
  - STT/TTS: prefer NVIDIA speech NIMs if usable, otherwise the provider's defaults.
  - Keep latency low: Nemotron Nano for voice turns, with short responses.
- **Fallback:** if live SIP isn't working by the integration checkpoint, ship voice notes plus a recorded call. Tell the human early.

### 7.4 Security posture (say it in the pitch)
- Messages carry minimal context plus an authenticated deep link. Full detail stays in the app.
- Audit log of every outbound and inbound message.
- Production path: WhatsApp Business / SMS / enterprise channels and self-hosted models, so plant data never leaves the site.

---

## 8. Deterministic engines (Core API; unit-tested)
1. **Drift detection:** per-sensor rolling baseline (robust median/MAD, or EWMA) + slope over multiple windows (1 h, 24 h, 7 d) + CUSUM for slow shifts. Output: `{z, slope, window, direction, since}`.
2. **Sensor sanity:** compare to neighbors (same zone, redundant sensors) and to simple physics (e.g. CHW ΔT vs flow vs load energy balance; return > supply). Output: confidence 0–1 plus a reason.
3. **Redundancy / topology engine:** graph over power and cooling. `simulate_action(open breaker X | put UPS-2 in bypass | stop pump P-2)` returns the loads that lose a source and the resulting N-level per load. Pure function, heavily tested. This is what the Guardian relies on.
4. **Alarm correlation:** time window + topology ancestry + known cause patterns (upstream trip → downstream alarms). Output: clusters, a candidate root cause and suppressed child alarms. Track ISA-18.2-style alarm-health metrics (alarms per 10 minutes) so we can show "47 → 1".
5. **Time-to-threshold:** fit the recent trend (linear, or exponential/thermal-mass model for temperature) and project the ETA to a limit with a confidence band. It must state its assumptions ("no chiller restarts; load constant").
6. **Round re-ranker:** risk score = criticality × anomaly × staleness × open items. The LLM only writes the human rationale.

---

## 9. Frontend design direction

**Feel:** native iOS quality, calm under pressure. Think Apple Health × Flighty × Apple Wallet, not Grafana.
- **Pre-design research:** use the **Mobbin MCP** to pull references before building screens. Search for:
  - Flighty (live status / Live Activity-style progress → incident countdown)
  - Apple Health (per-metric detail with a baseline band → asset sensor detail)
  - Apple Wallet passes (→ the asset card you get when you tap a tag)
  - Linear mobile / Things 3 (→ owned task lists, handover checklist)
  - Find My (→ "where is it / who's near")
  - Uber / DoorDash live order status (→ escalation ladder progress)
  - iOS Control Center (→ redundancy pill)

  Save the chosen references to a Mobbin collection and note in `docs/design.md` which pattern each screen borrows.
- If an **apple-design** (or similar frontend/design) skill is available, load it and follow Apple HIG: SF Pro / system font stack, 44pt+ tap targets (**make them 56pt+ for gloved hands**), Dynamic Type, haptics via the Vibration API where supported, sheets instead of pages, and semantic colors.
- **Visual language:**
  - Dark mode default. Data halls are bright, but dark reduces glare on tablets and looks premium on a projector. Provide light mode too.
  - Severity uses color *and* shape/label (accessibility).
  - One accent color for "owned by you".
  - Numbers with units, always paired with "vs your baseline" context.
  - Motion is meaningful only: the countdown ring, check-off animations, a card "lifting" when it escalates.
- **Screens (P0):**
  1. Shift start ("You've inherited 3 items"), a swipeable stack of handover cards with Confirm.
  2. Round list (re-ranked, with "why first" chips).
  3. Asset page (the hero screen; Wallet-pass-like header, live state, drift chip, notes, procedures, history).
  4. Reading entry (giant keypad, voice button, instant baseline feedback).
  5. Procedure run (step card, GO/HOLD banner, reasoning sheet, override flow).
  6. Warning detail (owner, deadline ring, evidence, escalation ladder progress, message thread mirror).
  7. Incident mode (focused, single card, time-to-limit, EOP, who's been contacted).
  8. Handover review and send.
- **Presenter screens:** Demo Director (dense controls are fine) and Agent Trace Viewer (beautiful: plan checklist ticking, tool calls as cards, reasoning collapsed under "Why").
- **AR (P2):** MindAR image targets using the printed equipment photos. Labels anchored over the image: name, status dot, drift chip, open-note count, HOLD banner. Build it as a separate route so it can't break the core app.
- **NFC on iPhone:** iPhone reads NDEF URL tags natively in the background. Write the asset URL to the tag and tapping opens the page in Safari, with no Web NFC needed (Web NFC is Android Chrome only). QR codes are the universal fallback.

---

## 10. Inference, Brev, and fine-tuning

**Phase A (start here; decided):** hosted **build.nvidia.com** endpoints (OpenAI-compatible, base URL `https://integrate.api.nvidia.com/v1`) with an `NVIDIA_API_KEY`.
- Free for prototyping through the NVIDIA Developer Program, rate-limited to about 40 RPM.
- **No local model downloads.** Team laptops can't serve these models well.

Move to Phase B only if rate limits or latency hurt the demo, or once the core is done.

**Phase B (once the core works; recommended):** **self-host Nemotron Nano on a Brev GPU** using vLLM or a NIM container.
- **Why:**
  - Stable latency for the live demo.
  - No rate limits.
  - A real proof point for the pitch: "runs on-site; plant data never leaves the building", which matters to security-sensitive operators.
  - It also uses NVIDIA's own stack end to end.
- Switch per agent by changing the base URL in the model config.
- Keep hosted Super for the heaviest reasoning if the Brev GPU can't fit it.
- Starting points: Brev has a launchable for Nemotron 3 Nano on vLLM, and NIM deploy guides (port-forward 8000).

**Fine-tuning:** honest recommendation: **not on the critical path.** Prompting plus tools plus deterministic engines will beat a rushed fine-tune. Do it only if P0 and P1 are done with time to spare. Best candidate:
- **LoRA fine-tune Nemotron Nano** on *synthetic* pairs for (a) tech voice-note → structured entry and (b) MOP step → precondition predicates.
- Generate the data with Nemotron Super from our seed procedures.
- Train on Brev and evaluate against the golden set before and after.
- Pitch line: "a small on-site model specialized for our schema: faster and cheaper than the big model at equal accuracy." Only claim this if the eval shows it.
- Alternative non-LLM training (cheaper, very defensible): train a small anomaly or fault classifier on the LBNL chiller fault datasets and use it as an additional Investigator tool.

---

## 11. Parallel workstreams

**Phase 0: Contracts (lead agent, ~1–2 h, blocking)**
- Scaffold the pnpm + Turborepo monorepo (§4.3 layout) and shared `tsconfig`, ESLint and Prettier.
- `packages/contracts` (zod-first): DB schema and initial `supabase/migrations` **with GRANTs and realtime publication per §4.2**, OpenAPI generated from zod, event types (`reading.new`, `drift.detected`, `alarm.raised`, `incident.opened`, `warning.created|acked|escalated`, `procedure.step_checked`, `handover.drafted|confirmed`, `message.inbound|outbound`), agent tool JSON schemas, scenario YAML schema.
- Seed site JSON and the first scenario YAML (S1).
- `docker-compose.yml`, `.env.example`, root scripts (`pnpm dev`, `pnpm demo`, `pnpm test`, `pnpm eval`); a Makefile wrapper is optional.
- Mock server generated from OpenAPI so the frontend and comms work can start immediately.

**Phase 1: Parallel build (each with its own branch/worktree)**
| WS | Owner dirs | Scope | Depends on |
|---|---|---|---|
| WS1 Sim + Engines | `services/sim`, `services/core/engines` | Simulator, scenarios S1–S5, all §8 engines with tests | Contracts |
| WS2 Core API + DB | `services/core` (except engines), `supabase/` | Supabase migrations (grants + RLS + realtime), Hono REST, SSE/realtime, event bus, audit log, seed loader | Contracts |
| WS3 Agents | `services/agents` | AI SDK provider + shared rate limiter + cache, tool registry + MCP server, A1–A6, trace store, golden evals | Contracts, tool mocks |
| WS4 Field App | `apps/field` | Mobbin research → design doc → P0 screens against the mock API → realtime | Contracts, mock server |
| WS5 Comms | `services/comms` | Spectrum setup (terminal provider first, then iMessage), app cards, ladder state machine, groups, voice bridge | Contracts, Photon creds |
| WS6 Demo + Trace | `apps/director`, `data/`, `docs/` | Demo Director, Agent Trace Viewer, MOP PDFs, QR/NFC printables (PDF sheet + an on-screen "tag wall" page for testing before printing), demo cache, README, judging map | Contracts |

**Integration checkpoints**
- **C1 (end of Phase 1 slice):** S1 runs end-to-end:
  1. sim drift
  2. engine flags
  3. Investigator creates a warning
  4. the app shows it on the asset page
  5. an iMessage card arrives on a real phone
  6. reply "own" → app updates
- **C2:** S2 Guardian HOLD works live from a compiled PDF procedure.
- **C3:** S3 incident: correlation, countdown, group chat, outbound voice call.
- **C4:** Handover flow + polish + demo-mode hardening + rehearsal ×3.

**Suggested timeline (assumes ~24–36 h; adjust to the real schedule)**
| Phase | Share of time | Exit criteria |
|---|---|---|
| 0 Contracts | 5% | Contracts committed, mocks running |
| 1 Thin slice | 25% | C1 passes |
| 2 Depth | 35% | C2 + C3 pass, all P0 done |
| 3 P1/P2 + polish | 20% | Trace Viewer beautiful, AR/voice if feasible |
| 4 Harden + rehearse | 15% | Demo mode bulletproof, 3 clean rehearsals, video backup recorded |

---

## 12. Demo mode and quality

- **Deterministic:** `DEMO_MODE=1` loads the seed site, fixes the RNG seeds, and drives the simulated clock from the Director. Scenarios can be started, paused, stepped and reset in under 5 s.
- **LLM cache:** record agent responses during rehearsals, keyed on (agent, inputs hash). With `DEMO_CACHE=prefer`, use the cache when present and fall back to live. With `DEMO_CACHE=only`, never call the network. The Trace Viewer labels cached vs live honestly.
- **Comms fallback:** if Photon or phones fail, mirror the messages into an in-app "phone" panel and use the terminal provider.
- **Evals:** `pnpm eval` runs the golden scenarios (against the LLM cache by default; `EVAL_LIVE=1` for live calls) S1–S5 and prints pass/fail per agent assertion (§6.4). Run it in CI on every merge to main.
- **Tests:** engines (vitest, fast-check property tests for the topology engine), API contract tests, Playwright smoke test of the P0 screens on a mobile viewport.
- **Observability:** the `agent_trace` table plus the Trace Viewer, and structured logs. Show agent latency per step in the Trace Viewer (it looks good for the NVIDIA track).
- **Performance:** asset page under 1 s; Guardian verdict under 4 s (show a skeleton with the deterministic result first, then the LLM reasoning).

---

## 13. Judging map (put this in `docs/judging.md` and in the pitch)

| Track | Criterion | Where it shows up in the demo |
|---|---|---|
| **NMC²** | Missed warning | S1 drift → owned warning → escalation; S4 battery creep |
| | Unclear handoff | I-PASS walk-through handover with read-back; incident group chat across organizations |
| | Wrong info at the wrong time | Tap-to-asset context; Guardian HOLD; time-to-limit; sensor sanity (S5) |
| | Stay one step ahead | Multi-horizon precursors + projection; risk-ranked rounds |
| **NVIDIA** | Beyond a chatbot | Event-triggered agents; no prompt needed |
| | Multi-step workflows | Investigator / Incident Coordinator visible plans in the Trace Viewer |
| | Tool integration | 15+ tools incl. topology engine, CMMS, Photon messaging and voice, VL document parsing |
| | Real-world applicability | Mirrors CME, Azure, NIRS, Optus, Heathrow outages; advisory-only; self-hosted on Brev |
| **Photon** | Best use of API | App cards updated live, polls/replies for ACK, read receipts in the escalation logic, auto-created and renamed incident groups with membership, cross-provider (iMessage + WhatsApp/SMS) |
| | Voice Call | Outbound wake-up call with verbal read-back; inbound "call the plant" Q&A and note logging |

---

## 14. Reference docs (verify before use)
- Photon docs index: https://photon.codes/docs/llms.txt · Spectrum getting started: https://photon.codes/docs/spectrum-ts/getting-started · Voice (SIP): https://photon.codes/docs/spectrum-ts/providers/voice · App cards: https://photon.codes/docs/spectrum-ts/content/app · Groups/membership/rename pages (see index) · Beta voice cookbooks (LiveKit/ElevenLabs/Retell/Twilio) from the index
- Nemotron models & API: https://build.nvidia.com (model cards: Nemotron 3 Super, Nano, 3.5 Lightning, 3.5 Bolt, Nano VL) · Nemotron usage cookbook: https://docs.nvidia.com/nemotron/latest/usage-cookbook/README.html
- Brev: deploying NIMs https://docs.nvidia.com/brev/latest/guides/inference-deployment/deploying-nims · vLLM + Nemotron 3 Nano: https://vllm.ai/blog/run-nvidia-nemotron-3-nano
- NeMo Agent Toolkit deprecation notice (do not depend on it): https://docs.nvidia.com/nemo/agent-toolkit/1.9/index.html
- MindAR (web AR image tracking), LiveKit Agents + SIP, Supabase Realtime: use their current docs
- LBNL fault-detection datasets (optional realism): search "LBNL FDD datasets"

---

## 15. What the human needs to provide (ask for these up front)
**Already done**
- ✅ Supabase project created (`hrkuvnanhchdvinviaii`, settings in §4.2).
- ✅ Decisions: TypeScript + Vercel AI SDK; hosted build.nvidia.com first; no local model downloads.

**Still needed**
1. **NVIDIA API key** from build.nvidia.com (free NVIDIA Developer Program) → `NVIDIA_API_KEY`.
2. **Supabase keys:** the human copies the publishable/anon key and the secret/service key from Project Settings → API into `.env`. Give the coding agent Supabase MCP access if possible. **Never paste secret keys into chat or commit them.**
3. **Photon:** account at app.photon.codes with the hackathon promo code. Create a project and get the **project ID and secret**. Provision an **iMessage line** (required for voice). Set up webhook secrets if we use webhooks.
4. **Phones for the demo:** at least two iPhones (tech + on-call chief), plus one judge volunteer's number if they agree. Every recipient must opt in.
5. **Voice:** a LiveKit Cloud account (or ElevenLabs/Retell, whichever Photon's cookbook path is smoothest) and, if needed, STT/TTS provider keys.
6. **Brev account** (hackathon credits), only if we reach Phase B (§10).
7. **Physical props, later:** printed equipment photos with QR codes (we generate the printables). Until then, test using the on-screen "tag wall" page. Optional: NTAG213/215 NFC stickers; an iPhone can write URL tags with the free NFC Tools app.
8. **Open decisions:** final product name, hackathon duration and team size (to tune §11's timeline), and which teammate presents.
