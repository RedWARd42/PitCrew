# Advisory agents

The seeded workflows use the same deterministic engine results as the field app. Traces label these as `deterministic`; they do not pretend a model was called. They record tool inputs, results and concise decision summaries, never private model reasoning.

`structuredAgent` uses a process-wide 30 RPM queue, AI SDK retries, a bounded timeout, Zod validation with one regeneration, and a disk cache keyed by model, agent and canonical inputs. `only` mode never calls a network. `prefer` reads valid cache records first. Live mode requires `NVIDIA_API_KEY` and an accessible `NEMOTRON_MODEL`. The core commits deterministic outcomes immediately, then uses `augmentTrace` to enrich summaries in the background for Investigator, Guardian, Coordinator, Scribe and Handover workflows. Model narration cannot change an owner, deadline, structured note, or deterministic verdict.

`runToolAgent` provides an eight-step read-only AI SDK loop. `compilePdf` sends a PDF to the configured vision model, validates extracted steps and always marks the result unapproved. Both are callable server-side integration functions; the seeded compiler uses precompiled, reviewed JSON. PDF extraction and hosted inference require live account verification.

Model availability: [NVIDIA’s Nano page](https://build.nvidia.com/nvidia/nemotron-3-nano-30b-a3b) currently marks its free endpoint deprecated. Configure an account-accessible model and endpoint before live rehearsal. No local model downloads are used. Vision transport support depends on the selected endpoint.

The shared HTTP/MCP registry exposes factual tools and `add_note` through the core command gateway. Write and communication tools use per-operation schemas and a queued core advisory gateway, which validates references, audits changes and persists state. Without that gateway they reject the call. Communications obey the comms mode and recipient allowlist; the default terminal provider is clearly simulated. No tool operates plant controls. `pnpm --filter @groundtruth/agents mcp` starts a stdio MCP server; keep its stdout reserved for JSON-RPC.

`pnpm eval` executes S1–S5 without live inference by default. `EVAL_LIVE=1` additionally validates live trace narration and should only be used with an authorized account.

Verified integration references: [AI SDK tool loops](https://ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling), [OpenAI-compatible provider](https://ai-sdk.dev/providers/openai-compatible-providers), and [MCP TypeScript server](https://modelcontextprotocol.io/docs/develop/build-server). Package types are the final check for the installed SDK major versions.
