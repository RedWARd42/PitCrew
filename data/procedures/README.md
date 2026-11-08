# Seed source documents

`source/` contains six fictional, single-page PDFs: five current maintenance/emergency procedures and one superseded UPS revision. Each includes a step table, local verification instructions, a simplified one-line sketch, a margin note and revision metadata. These are demonstration documents, not real operating procedures.

`compiled.json` contains reviewed seed procedure data; `sources.json` maps each exact PDF SHA-256 hash to the corresponding revision. Regenerate from the repository root using `pnpm exec tsx data/procedures/generate-pdfs.ts`. The generator is TypeScript and requires no PDF dependency.

`GET /api/procedures/compile` lists downloadable sources. Add `?source=MOP-UPS` to fetch a PDF. `POST` accepts multipart fields `file` (PDF, maximum 10 MB) and optional `title`. Exact known hashes load seed data with an explicit `deterministic-seed` label. Other PDFs need live model mode and server credentials. Every compilation result is a separate, unapproved review artifact; the endpoint cannot replace approved procedures or operate equipment.

Generation QA: all six PDFs were rendered with bundled PDFium. The UPS document was inspected at full size after fixing row divider placement. All documents have the same verified page template and fit on one page.
