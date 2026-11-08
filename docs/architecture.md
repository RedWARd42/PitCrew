# Architecture

The field app and Core API share one Next.js process for the hackathon. The API validates commands with Zod and serializes state transitions. SSE subscribers receive the validated snapshot after each transition. The simulator is the only demo component that changes simulated plant state. Agent tools expose advisory and work-management operations.

The six deterministic engines compute drift, sanity, topology impact, alarm clusters, threshold projections, and round priority. Agent traces store tool inputs, results, and concise explanations. They do not expose private model reasoning. Offline workflows remain available when hosted inference fails and identify their mode honestly.

The seed fixes the RNG and simulated clock. Clock steps drive both thermal evolution and escalation timers; wall-clock speed does not change scenario results. A transaction snapshots state before applying a command, validates the result, and rolls back invalid transitions. HOLD overrides require a reason and are audited. Superseded procedures cannot be overridden.

The local singleton is intended for a single demo server. Serverless replicas and multiple workers need a durable shared command queue and database transaction locking before production use. SSE reconnects fetch the current full snapshot. Supabase persistence is opt-in; no schema or rows are sent to a remote project in demo mode.

The service-role key stays on the server. Operational tables have RLS and no browser grants; the field app reads through the API. Live deployment requires authentication and per-site authorization in addition to the demonstration’s presenter token. Physical control adapters are deliberately absent.
