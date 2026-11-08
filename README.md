# PitCrew

Sector agent teams investigate developing data-center issues, share evidence, and dispatch qualified technicians only when physical work is needed. Technicians receive a prepared case, record their findings, and escalate without losing completed work.

The primary experience is **Overview → Sector evidence → Work queue → Field checks → Lead handoff**. It uses a monochrome responsive interface, sector check-ins, equipment and qualification-aware routing, and an inspectable history of agent tools and human actions.

See [the sector operations demo](docs/sector-operations.md) for the demo flow, research, architecture, and explicit simulation boundaries. Nemotron runs the investigator and dispatcher through real server-side tools when configured; the sentinel and dispatch eligibility checks are deterministic. Shared memory and tickets currently live in the server process.

The earlier field rounds and adaptive investigation screens remain at `/shift` and `/investigate/CH-3`; the new sector experience is at `/`, `/tickets`, `/team`, and `/activity`. The setup notes below also describe those earlier integrations.

## Run the seeded demo

Requires Node 22 and pnpm 10.28.2.

```sh
pnpm install
pnpm demo
```

Open [PitCrew](http://localhost:3000). Select **Demo controls → Cooling drift**, then follow the case into **Work queue**. On a phone, use Maria Santos to accept and record a field check; escalate to Dev Morgan and inspect the generated handoff. **Sensor mismatch** demonstrates an agent-only case; **No sector coverage** demonstrates qualified senior dispatch. See the [five-minute demonstration](docs/sector-operations.md#five-minute-demonstration).

With `NVIDIA_API_KEY` configured, the sector investigator and dispatcher use `nvidia/nemotron-3.5-lightning-30b-a3b` by default (`NEMOTRON_FLEET_MODEL` overrides it). Without credentials, the same flow runs with clearly labeled evidence rules. No GPU or Brev setup is required. Personnel, telemetry, notifications, and physical work are synthetic. Fleet state is currently in memory; the earlier Supabase integration described below does not persist it.
The app uses Next.js route handlers for the Core API, a choice explicitly allowed by the plan. All services share Zod contracts; the simulator and engines run on the server. Agents cannot alter plant controls. Procedure completion records human work and never actuates equipment.

## Verify

```sh
pnpm contracts
pnpm typecheck
pnpm test
pnpm eval
pnpm build
```

Mobile browser checks are in `tests/e2e`; run `pnpm exec playwright test` after installing Chromium with `pnpm exec playwright install chromium`. The evaluation runner uses deterministic scenarios by default. A deterministic template is labeled deterministic; it is not presented as a recorded model response.

## Configure real services

Copy `.env.example` to `.env` at the repository root. Secrets belong only in that ignored file. Keep the default `DEMO_MODE=1`, `DEMO_CACHE=only`, and `COMMS_MODE=terminal` until live setup is complete. Never use a `NEXT_PUBLIC_` prefix for a service key.

- **Supabase:** use the existing `hrkuvnanhchdvinviaii` project. Apply the SQL in `supabase/migrations` using Supabase CLI or SQL editor. No new project is needed. The migration enables RLS, grants the server role access explicitly, and publishes operational tables for realtime. The app uses its server API and SSE, so no anonymous database grants are needed. Live persistence requires `DEMO_MODE=0` and server credentials.
- **NVIDIA:** set `NVIDIA_API_KEY`, `NEMOTRON_BASE_URL`, and an accessible `NEMOTRON_MODEL`. The model named in the plan currently shows a deprecated free endpoint in the catalog. Verify availability in your NVIDIA account before choosing live inference. The provider is configurable and has bounded calls and a deterministic fallback.
- **Photon:** the current account uses Beta 2.0. Configure its project ID and API key (`PHOTON_API_KEY`, with the older `PHOTON_PROJECT_SECRET` name accepted as a fallback), plus the destination's `PHOTON_WEBHOOK_SECRET`. Configure opted-in phones in `PHOTON_PEOPLE_JSON` and `PHOTON_RECIPIENT_ALLOWLIST`. Enable `COMMS_MODE=live` only when ready to send. See [Photon destination settings](docs/photon-setup.md).
- **Voice:** ElevenLabs Agents replaces the planned LiveKit worker. Use `VOICE_PROVIDER=elevenlabs` and leave `VOICE_MODE=simulated` until the agent, imported Photon SIP phone number, scoped tools and opted-in recipient are ready. See [ElevenLabs setup](docs/elevenlabs.md).

Live provider behavior requires account-side setup and a real rehearsal. The procedure screen offers source PDFs and a bounded PDF upload/review flow; unfamiliar PDFs require a configured vision endpoint. SIP voice, live vision extraction, AR, gauge photos, and Brev hosting must not be claimed in a pitch unless separately configured and tested. Read [implementation status](docs/status.md) before using the original demo script.

## Code map

| Directory             | Purpose                                                |
| --------------------- | ------------------------------------------------------ |
| `apps/field`          | Next.js field app, Director, traces, phone mirror, API |
| `packages/contracts`  | Zod schemas, generated OpenAPI and tool contracts      |
| `services/core`       | State machine, deterministic engines, persistence      |
| `services/sim`        | Seeded plant, fault timelines, demo clock              |
| `services/agents`     | Workflow tools, provider, cache, MCP, scenario evals   |
| `services/comms`      | Escalation ladder, read-backs, Spectrum adapter        |
| `supabase/migrations` | Server-only database schema, grants, realtime          |
| `data`                | Seed site, scenarios, procedures                       |

See [architecture](docs/architecture.md), [design research](docs/design.md), and [judging map](docs/judging.md).
