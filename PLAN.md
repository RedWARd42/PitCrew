# Signal Swarm — Build Plan (HackUTD 2026)

> **For the coding agent reading this:** you are the **Orchestrator**. This file is the source of truth. Read it fully, then execute the waves in order. Within each wave, launch every listed workstream **in parallel** (Claude Code: launch all Task/Agent calls in a single message, each with worktree isolation; Codex: one task per workstream, each on its own branch). Do not do a workstream's work yourself unless its agent fails twice.

---

## 0. TL;DR

**Product:** An Android anti-scam companion. A small robot ("the Hive") sits over Google Messages. When a suspicious text appears, it releases drones that fly to the exact message bubble, sender header, or link, scan it, and land with a verdict. Tap a drone → plain-language explanation, honest confidence, and one-tap next steps. iPhone users get the same swarm through a Photon iMessage/SMS line ("forward it to the Swarm"), and family "guardians" get privacy-preserving alerts via Photon.

**Tracks:** T-Mobile (scam & fraud protection) + Photon API.

**Stack:**
| Layer | Tech | Dir |
|---|---|---|
| Android host app | Kotlin, AccessibilityService, TYPE_ACCESSIBILITY_OVERLAY windows, OkHttp, kotlinx.serialization | `android/` |
| Drone overlay UI | Vanilla HTML/CSS/JS in a transparent WebView (ported from existing `Signal_Swarm.html`) | `overlay/` |
| Detection backend | Python 3.11, FastAPI, T-Mobile baseline classifier, scikit-learn, Anthropic API (explanations only) | `backend/` |
| Intel data | CSV/JSON + build scripts | `data/`, `intel/` |
| Scenarios + eval | Python, YAML scenarios, adb injector | `scenarios/`, `eval/`, `scripts/` |
| Photon service | TypeScript, Bun, Photon Spectrum SDK (2.0) | `photon/` |
| Pitch | Markdown/slides, recorded video | `pitch/` |

---

## 1. Assumptions & human-only inputs

The agent cannot do these. The **human** does them in parallel with Wave 0 and drops the results where listed. Agents must work around missing items using mocks and fixtures. **Never block on a missing human input.**

| # | Human task | Put result in | Fallback if missing |
|---|---|---|---|
| H1 | Install Android Studio and create an AVD: **Pixel 8, API 34 or 35, "Google Play" system image** (it ships with Google Messages as the default SMS app). Boot it. | — | none (hard requirement for Android work) |
| H2 | Download T-Mobile's synthetic message set, scam taxonomy, and baseline classifier | `data/tmobile/` (any format; agents will inspect it) | Agent E generates a stand-in synthetic set; Agent C uses a TF-IDF+LR stand-in classifier |
| H3 | Sign up at app.photon.codes (promo `HACKWITHPHOTON`), create a project, get project ID/secret, and paste the Photon 2.0 hackathon guidelines / prize criteria | `.env` (`PHOTON_PROJECT_ID`, `PHOTON_PROJECT_SECRET`), `docs/photon-guidelines.md` | Agent F builds against Photon's **terminal provider** / a local mock |
| H4 | Anthropic API key | `.env` (`ANTHROPIC_API_KEY`) | Templated explanations (already required as a fallback) |
| H5 | One teammate's real phone number for the guardian/forwarding demo (the emulator has no real number) | `.env` (`DEMO_GUARDIAN_NUMBER`) | Demo the guardian alert in the terminal provider |
| H6 | Install `cloudflared` or `ngrok` for a public Photon webhook URL | — | Use Photon's WebSocket or long-lived-process mode if available |

**Time assumption:** plan written for ~14 working hours from T0. See §11 for the compressed ≤8h cut.

---

## 2. Demo we are building toward (3 minutes)

1. **Setup (10s):** Emulator showing Google Messages. The Hive robot sits bottom-right with a green "Protected" ring. Onboarding card: "Checked on-device first. Only redacted text ever leaves your phone."
2. **Hero smish (60s):** `make inject S=tmobile_account_lock`. A text arrives: "T-Mobile: your line will be suspended in 2 hrs. Verify: t-mobi1e-acct-verify.co/…". The user opens the thread. The Hive turns red and releases 4 drones in parallel:
   - **Angler** → sender header: "First-time sender, 10-digit long code. Real T-Mobile alerts come from short codes."
   - **Link** → URL: "Lookalike domain (`mobi1e` uses a 1, not an l). Registered 3 days ago."
   - **Pressure** → "suspended in 2 hrs": "Deadline pressure. Classifier category: Account-Suspension Smishing (taxonomy id)."
   - **Impersonator** → "T-Mobile": "Brand impersonation. Call the real T-Mobile: 611."
   - Risk 94, "Likely scam · 92% confidence". Tap a drone → its tab. Actions: **Report to 7726**, **Call real T-Mobile**, **Alert my guardian**, **Mark safe**.
3. **Pre-send guard (40s):** Scenario `otp_harvest`: "Hi, it's T-Mobile support, we just texted you a code, reply with it to confirm." A real-looking OTP arrives from a short code. The user starts typing the 6-digit code into the reply box. The **Warden** drone dives onto the compose box: "Hold up. This code unlocks your account. T-Mobile will never ask for it by text." Buttons: *Don't send* / *Send anyway*.
4. **Slow-burn drift (30s):** Scenario `wrong_number_crypto` plays 6 messages over 30s ("Is this Linda?" → friendly chat → "my uncle's trading app"). The **Drift** drone shows a risk sparkline climbing as the conversation moves toward money and off-platform contact.
5. **Guardian + iPhone (30s):** Tap "Alert my guardian" → the teammate's real phone gets a Photon message: "Signal Swarm blocked a likely bank-impersonation scam on Mom's phone. No message content was shared. Reply CALL to ring her." Then forward a scam to the Swarm's Photon number from an iPhone and get the verdict back in-thread.
6. **Honesty + accuracy (10s):** Slide with eval numbers vs the T-Mobile baseline (precision/recall per taxonomy category, false-positive rate on legit messages, calibration). Show one **legit** bank text: drones stay docked, "Checked on-device · looks safe".

---

## 3. Architecture

```
┌──────────────────────── Android emulator ────────────────────────┐
│ Google Messages (unmodified)                                      │
│        ▲ reads node tree (text + screen bounds)                   │
│ ┌──────┴──────────────── signal-swarm app ─────────────────────┐ │
│ │ SwarmAccessibilityService                                     │ │
│ │  ├─ MessagesParser  → bubbles[], header, compose box          │ │
│ │  ├─ ThreadBuffer    (RAM only, last 20 msgs per thread)       │ │
│ │  ├─ Prefilter       (on-device: safe? skip network)           │ │
│ │  ├─ Redactor        (PII out before any network call)         │ │
│ │  ├─ DraftGuard      (Warden: compose-box watcher)             │ │
│ │  ├─ ScanClient ─────────── HTTPS ───────────┐                 │ │
│ │  └─ OverlayController                       │                 │ │
│ │      ├─ FX window: full-screen WebView,     │                 │ │
│ │      │   NOT_TOUCHABLE (drones, beams)      │                 │ │
│ │      ├─ Hit windows: small touchable        │                 │ │
│ │      │   windows at each landed drone/Hive  │                 │ │
│ │      └─ Panel mode: FX window becomes       │                 │ │
│ │          touchable while a tab is open      │                 │ │
│ │ SwarmCallScreeningService (P1)              │                 │ │
│ └─────────────────────────────────────────────┼─────────────────┘ │
└───────────────────────────────────────────────┼───────────────────┘
                     adb reverse tcp:8000       │
┌───────────────────────────────────────────────▼───────────────────┐
│ backend/ (FastAPI :8000)                                          │
│  /v1/scan → analyzers (sender, link, pressure/classifier,         │
│             impersonation, drift, attachment) → ensemble →        │
│             calibrated score → LLM explainer (strict JSON,        │
│             evidence-only) → ScanResult                           │
│  /v1/guardian/alert → photon service                              │
│  /v1/feedback, /v1/reputation/bundle, /v1/healthz                 │
└───────────────▲──────────────────────────────┬────────────────────┘
                │ /internal/scan               │ /internal/guardian-alert
┌───────────────┴──────────────────────────────▼────────────────────┐
│ photon/ (Bun, :8787)  Photon Spectrum SDK                         │
│  inbound webhook: "forward to Swarm" → scan → reply (+ app card)  │
│  outbound: guardian alerts (category + risk only, no content)     │
└───────────────────────────────────────────────────────────────────┘
```

**Key technical decisions (do not relitigate):**
1. **Read via AccessibilityService**, scoped with `android:packageNames="com.google.android.apps.messaging"`. Not READ_SMS: we need on-screen bounds so drones can fly to bubbles, and this works with an unmodified Messages app.
2. **Draw with `TYPE_ACCESSIBILITY_OVERLAY`**, not `TYPE_APPLICATION_OVERLAY`. Accessibility overlays are trusted windows, so they're exempt from Android 12+ untrusted-touch blocking, and they don't need SYSTEM_ALERT_WINDOW.
3. **Two-layer overlay:** one full-screen, `FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE | FLAG_LAYOUT_IN_SCREEN | FLAG_LAYOUT_NO_LIMITS` transparent WebView for all animation, plus N small touchable "hit windows" (64dp) placed where drones land and over the Hive. When a tab panel opens, flip the FX window to touchable (remove NOT_TOUCHABLE) and dim the background; tapping the dim area closes it.
4. **Overlay UI is web** so it can be built and tested in a desktop browser with a mock event feed. Agent B never needs the emulator.
5. **Emulator ↔ backend via `adb reverse tcp:8000 tcp:8000`**, so the app calls `http://127.0.0.1:8000`. Add a network security config allowing cleartext to 127.0.0.1 only.
6. **Confidence comes from the calibrated ensemble, never from the LLM.** The LLM only words the explanation from the evidence it is given.
7. **Synthetic data only.** No real customer data anywhere. Scam domains in scenarios must not resolve to live sites (check with `dig`; prefer obviously-fake TLD combos).

---

## 4. Repo layout (Orchestrator creates in Wave 0)

```
signal-swarm/
├─ PLAN.md                 ← this file
├─ AGENTS.md               ← conventions (CLAUDE.md symlinks to it)
├─ Makefile                ← make doctor|backend|mock|overlay-dev|overlay-sync|android|inject|e2e|eval|check
├─ .env.example
├─ contracts/
│  ├─ scan.schema.json     ← JSON Schema: ScanRequest, ScanResult, Finding, Action
│  ├─ bridge.schema.json   ← Kotlin↔WebView messages
│  ├─ photon.schema.json   ← backend↔photon internal calls
│  ├─ types.ts             ← TS mirror (overlay + photon)
│  ├─ models.py            ← Pydantic mirror (backend)
│  ├─ Contracts.kt         ← Kotlin mirror (android) — copied into android/ by `make sync-contracts`
│  └─ fixtures/            ← canonical example payloads; contract tests validate all three mirrors against these
├─ android/                ← Gradle project, single :app module
├─ overlay/                ← web drone UI; `make overlay-sync` copies dist → android/app/src/main/assets/overlay/
├─ backend/
├─ intel/                  ← build scripts for data/
├─ data/
│  ├─ tmobile/             ← H2 drops files here (gitignored if large)
│  ├─ synthetic/           ← generated stand-in data
│  ├─ reputation/numbers.csv
│  ├─ brands.json          ← official contact directory
│  └─ domains.json         ← synthetic WHOIS/age table + brand domain list
├─ scenarios/*.yaml
├─ eval/
├─ scripts/                ← doctor.sh, inject.py, e2e.sh, dump_ui.sh
├─ photon/
├─ pitch/
└─ legacy/Signal_Swarm.html  ← the existing prototype (reference for visuals)
```

---

## 5. Contracts (frozen at tag `contracts-v1` after Wave 0)

Only the Orchestrator may edit `contracts/`. Workstream agents that need a change append a request to `contracts/CHANGE_REQUESTS.md` and keep working against the current contract with a local shim.

### 5.1 Drone roster
| id | Name | Color | Watches | Priority |
|---|---|---|---|---|
| `angler` | Angler | #fb923c | Sender: number type (long code / short code / toll-free / email / alphanumeric), reputation, contact status, first-time sender, sender/brand mismatch | P0 |
| `link` | Link | #38bdf8 | URLs: lookalike/homoglyph/punycode vs brand list, shorteners, risky TLDs, domain age (synthetic WHOIS table), path keywords (`verify`, `login`) | P0 |
| `pressure` | Pressure | #f87171 | Language: urgency, threats, secrecy, payment rails (gift cards, crypto, Zelle, wire), plus the T-Mobile classifier category | P0 |
| `impersonator` | Impersonator | #f472b6 | Brand/person impersonation; supplies "call the real one" from `brands.json`; also handles incoming calls | P0 |
| `warden` | Warden | #fbbf24 | **Outgoing** drafts: OTPs, gift-card codes, card numbers (Luhn), SSNs, passwords sent to an unknown or recently-suspicious thread | P1 |
| `drift` | Drift | #a3e635 | Thread trajectory: rapport → trust → off-platform → money; per-message risk series | P1 |
| `carrier` | Carrier | #4ade80 | Attachments, APK links, "shared document" lures | P2 |
| `scanner` | Scanner | #c084fc | QR codes and images in MMS | P2 |

### 5.2 ScanRequest / ScanResult (canonical TS; mirror exactly in JSON Schema, Pydantic, Kotlin)

```ts
type DroneId = "angler"|"link"|"pressure"|"impersonator"|"warden"|"drift"|"carrier"|"scanner";

interface Sender {
  raw: string;                       // as displayed, e.g. "+1 (469) 555-0182", "62884", "alerts@x.co"
  kind: "long_code"|"short_code"|"toll_free"|"email"|"alphanumeric"|"unknown";
  e164?: string;
  isContact: boolean;                // contacts' display names are NEVER sent; replaced by "CONTACT"
}

interface MessageIn {
  id: string;                        // stable on-device id: sha1(threadId + text + ordinal)
  direction: "in"|"out";
  text: string;                      // ALREADY REDACTED on device
  ts?: string;                       // ISO if parsed, else omitted
  hasAttachment?: boolean;
}

interface ScanRequest {
  requestId: string;                 // uuid
  client: "android"|"photon"|"web";
  mode: "incoming"|"outgoing_draft";
  sender: Sender;
  messages: MessageIn[];             // thread context, oldest→newest, max 20
  targetMessageId: string;           // message to explain (for drafts: id "draft")
  locale: string;                    // "en-US"
  redactions: { type: string; count: number }[];   // what the device removed (for the privacy receipt)
}

interface Evidence { kind: string; value: string; source: "heuristic"|"classifier"|"reputation"|"intel"|"llm"; }

interface Anchor {
  messageId: string;                 // or "header" / "draft"
  field: "sender"|"body"|"link"|"compose";
  span?: [number, number];           // char offsets into redacted text, for highlighting
}

interface Finding {
  drone: DroneId;
  severity: "info"|"low"|"medium"|"high";
  confidence: number;                // 0..1, from analyzer/ensemble, NOT the LLM
  title: string;                     // ≤ 60 chars
  explanation: string;               // ≤ 280 chars, plain language, 8th-grade reading level
  evidence: Evidence[];
  anchor: Anchor;
  whatWouldChangeMyMind?: string;    // honest-confidence line, e.g. "If this came from 611/short code 456, I'd trust it."
}

type ActionId = "report_7726"|"call_official"|"alert_guardian"|"block_sender"|"delete"|"mark_safe"|"dont_send"|"send_anyway";
interface Action { id: ActionId; label: string; payload?: Record<string,string>; primary?: boolean; }

interface ScanResult {
  requestId: string;
  verdict: "scam"|"suspicious"|"unsure"|"safe";
  riskScore: number;                 // 0..100
  confidence: number;                // 0..1 calibrated
  category?: { id: string; label: string; source: "tmobile_taxonomy"|"fallback" };
  summary: string;                   // 1–2 sentences
  findings: Finding[];               // 0..8, at most one per drone
  actions: Action[];
  riskSeries?: number[];             // drift: per-message risk for the thread
  privacy: { fieldsReceived: string[]; retained: false; llmUsed: boolean };
  latencyMs: number;
  modelVersion: string;
}
```

### 5.3 Bridge (Kotlin ↔ overlay WebView)
Kotlin → JS: `webView.evaluateJavascript("window.swarm.dispatch(" + json + ")")`
JS → Kotlin: `window.SwarmBridge.post(JSON.stringify(msg))` via `@JavascriptInterface`

```ts
// Kotlin → JS
type ToJs =
 | { t:"init"; density:number; screenW:number; screenH:number; insets:{top:number;bottom:number} }
 | { t:"screen"; visible:boolean; threadKey?:string; header?:Rect; compose?:Rect; send?:Rect;
     bubbles:{ messageId:string; direction:"in"|"out"; rect:Rect; linkRects?:Rect[] }[] }   // rects in SCREEN PX
 | { t:"scanStarted"; messageId:string; drones:DroneId[] }
 | { t:"scanResult"; result:ScanResult }
 | { t:"localSafe"; messageId:string; reason:string }            // prefilter said safe, no network call
 | { t:"draftRisk"; result:ScanResult }                          // Warden
 | { t:"incomingCall"; number:string; result:ScanResult }         // P1
 | { t:"privacyReceipt"; requestId:string; payload:ScanRequest }  // exactly what left the device
 | { t:"hide" };                                                 // Messages not in foreground

// JS → Kotlin
type ToKotlin =
 | { t:"ready" }
 | { t:"hitTargets"; targets:{ id:string; rect:Rect }[] }          // where drones/Hive are now (screen px)
 | { t:"panel"; open:boolean }                                   // flip FX window touchability
 | { t:"action"; id:ActionId; payload?:Record<string,string>; requestId:string }
 | { t:"log"; level:"d"|"w"|"e"; msg:string };

type Rect = { x:number; y:number; w:number; h:number };
```
JS converts screen px → CSS px by dividing by `density`.

### 5.4 Backend HTTP
| Method | Path | Body → Response |
|---|---|---|
| POST | `/v1/scan` | ScanRequest → ScanResult (p95 < 1.5s with LLM, < 150ms without) |
| POST | `/v1/guardian/alert` | `{requestId, category, riskScore, userAlias}` → `{sent:boolean}` |
| POST | `/v1/feedback` | `{requestId, label:"scam"|"safe"}` → 204 (aggregate counters only, no text) |
| GET | `/v1/reputation/bundle` | → `{salt, hashes:[sha256(salt+e164)], version}` for on-device lookup (P1) |
| GET | `/v1/healthz` | → `{ok, classifier:"tmobile"|"fallback", llm:boolean}` |

Auth: header `X-Swarm-Key: $SWARM_API_KEY` on everything except healthz.

### 5.5 Photon internal
- photon → backend: `POST /v1/scan` with `client:"photon"` (the photon service redacts first using the same rules, via a TS port of the redactor).
- backend → photon: `POST http://127.0.0.1:8787/internal/guardian-alert` `{to, userAlias, categoryLabel, riskScore}` with header `X-Swarm-Key`.

---

## 6. Waves and parallelism

```
T0 ─ Wave 0 (≈45m) ─┬─ ORCH: scaffold + contracts + mocks + Makefile + AGENTS.md
                    └─ S1 (spike agent, needs emulator): UI-tree dumps & risk checks
T+0:45 ─ Wave 1 (≈5h, 7 agents in parallel)
          A1 Android Reader │ A2 Android Overlay Host │ B Overlay Web UI │ C Backend
          D Intel Data      │ E Scenarios + Eval       │ F Photon
T+6h ─ Wave 2 (≈1.5h) ORCH integration + QA agent: hero scenario end-to-end
T+7:30 ─ Wave 3 (≈4h, 6 agents in parallel)
          A1→Warden │ A2→Calls │ B→polish/drift/receipt │ C→drift+calibration │ F→guardian+app card │ H→pitch
T+11:30 ─ Wave 4 (≈2h) freeze, QA full pass, eval report, record demo video
```

**Rules for parallel work**
- Each agent works in its own git worktree on branch `ws/<agent-id>` and **only edits the directories it owns** (listed per agent). Anything else → `contracts/CHANGE_REQUESTS.md` or a note in its final report.
- Every agent builds against **mocks/fixtures** first, so no one waits on anyone.
- Merge order at each wave end: `C → D → E → B → A1 → A2 → F → H`. The Orchestrator runs `make check` after each merge.
- Each agent ends with a report: done / how to run / tests run / known issues / requests.

---

## 7. Wave 0 — Orchestrator + Spike (parallel pair)

### ORCH tasks (sequential, fast)
1. `git init`, create the §4 layout, move the existing prototype to `legacy/Signal_Swarm.html`.
2. Write `AGENTS.md` (symlink `CLAUDE.md`): ownership table from §8, commit style, "no real customer data", "never log message text", "run `make check` before reporting".
3. Write all contract files in §5 plus `contracts/fixtures/`:
   - `scan_request_tmobile_lock.json`, `scan_result_tmobile_lock.json` (4 findings: angler, link, pressure, impersonator)
   - `scan_result_safe_bank.json`, `scan_result_unsure.json`, `scan_result_warden_otp.json`, `scan_result_drift.json`
   - `bridge_screen_example.json` (3 bubbles, header, compose rects for a 1080×2400 screen, density 2.625)
4. Contract tests: `contracts/test_contracts.py` (jsonschema validates fixtures; Pydantic parses them), `contracts/test_types.ts` (tsc compiles a fixture import).
5. `backend/mock_server.py`: FastAPI that serves the matching fixture for `/v1/scan` by keyword (`T-Mobile` → lock fixture, `code` → warden, default → safe). Also used in Wave 1 by A1/A2/F.
6. Android skeleton that builds: Kotlin, minSdk 29, target 35, packages `reader/ privacy/ net/ overlay/ guard/ calls/ ui/`, each with stub classes; `accessibility_service_config.xml`; manifest entries; `network_security_config.xml`; Gradle deps (OkHttp, kotlinx-serialization, coroutines, androidx.webkit). Copy `Contracts.kt` in. `./gradlew assembleDebug` must pass.
7. Overlay skeleton: `overlay/index.html`, `overlay/src/`, `overlay/dev/mock-feed.js` that replays `bridge_screen_example.json` + `scan_result_tmobile_lock.json` over a screenshot background `overlay/dev/messages_bg.png` (S1 provides it).
8. `Makefile` targets and `scripts/doctor.sh` (checks adb, emulator running, `com.google.android.apps.messaging` installed and default SMS app, Java 17, Python 3.11, Bun).
9. `.env.example` with every variable in this plan.
10. Commit, tag `contracts-v1`.

### S1 — Spike agent (needs the emulator; runs alongside ORCH)
**Goal:** de-risk reading Google Messages before A1 builds on assumptions.
1. `adb emu sms send 4695550182 "T-Mobile: your line will be suspended in 2 hrs. Verify: t-mobi1e-acct-verify.co/a8f"` → open the thread on the emulator.
2. `scripts/dump_ui.sh` → `adb shell uiautomator dump /sdcard/ui.xml && adb pull`. Capture **6 fixtures** into `android/app/src/test/resources/fixtures/`: conversation list; a thread with 1 incoming; a thread with 6 mixed in/out; a thread scrolled mid-way; a thread with text typed in the compose box; light and dark theme if time allows.
3. Write `docs/messages-ui-notes.md`: which nodes hold bubble text (text vs contentDescription), how incoming/outgoing can be distinguished (bounds x-position / content-desc pattern / resource-id if present), the header node for sender, the compose EditText, and the send button. Note which signals are stable without resource IDs.
4. Test alternate sender formats: `adb emu sms send` with a short code (`62884`), a toll-free number (`8885550100`), and an **email-like or alphanumeric sender**. Record what works. If the email sender fails, document that and recommend the fallback (scenario uses the carrier gateway body format `FRM:alerts@… MSG:…`, and Angler parses it).
5. Test `adb emu gsm call 8885550199` and confirm an incoming call shows.
6. Take a clean screenshot of a thread → `overlay/dev/messages_bg.png` (1080×2400) for Agent B.
7. Confirm `adb shell settings put secure enabled_accessibility_services …` works for a debug service.

**Done when:** fixtures + notes committed, and a go/no-go recorded in the notes for each risk.

---

## 8. Wave 1 — seven parallel workstreams

### A1 — Android Reader & Privacy
**Owns:** `android/app/src/main/java/**/reader/`, `privacy/`, `net/`, plus their tests. Does **not** touch `overlay/` Kotlin.
**Build:**
1. `SwarmAccessibilityService`: subscribes to `typeWindowStateChanged | typeWindowContentChanged | typeViewScrolled | typeViewTextChanged`, `canRetrieveWindowContent=true`, `flagReportViewIds|flagRetrieveInteractiveWindows`, `notificationTimeout=100`. Debounces 120ms. Emits a `ScreenModel` (`header`, `bubbles[]` with screen-px rects and link sub-rects where possible, `compose`, `send`) to `OverlayController` (A2's interface, stubbed in Wave 0).
2. `MessagesParser`: pure function `parse(rootSnapshot) → ScreenModel`, driven by the S1 notes. **Unit-tested against every S1 fixture XML** (write a small XML→fake-node adapter for tests). Must not rely solely on resource IDs.
3. `ThreadBuffer`: in-memory map threadKey → last 20 messages, deduped by message id. Cleared when the service stops. Never written to disk.
4. `Prefilter` (on-device): returns `LOCAL_SAFE` if sender is a contact AND no URL AND no money/credential/urgency keyword AND not a short-code OTP context; otherwise `ESCALATE`. Emits `localSafe` to the overlay.
5. `Redactor`: replaces contact display names → `CONTACT`; card numbers (Luhn) → `<CARD>`; SSN → `<SSN>`; emails in the body (except the sender) → `<EMAIL>`; street addresses (simple regex) → `<ADDR>`; OTP-looking 4–8 digit codes → `<CODE:n>` (keep length, since it's a signal). Keeps URLs and the sender number. Returns counts. Table-driven unit tests (≥25 cases).
6. `ScanClient`: OkHttp POST `/v1/scan` with `X-Swarm-Key`, 4s timeout, 1 retry, cancels in-flight scans for the same thread when a newer one starts. Caches results by message id for the session (RAM).
7. Scan trigger: when a thread is visible and the newest incoming message is unscanned and escalated → scan with full thread context. Also sends `privacyReceipt` with the exact payload.
8. Logging: `Log.d("SWARM", …)` with event names only (`scan_started id=… drones=…`, `scan_complete risk=…`). **Never log message text.**

**Acceptance:** `./gradlew testDebugUnitTest` passes; on the emulator with `make mock`, injecting the hero SMS produces `scan_complete risk=94` in logcat within 2s of opening the thread.

### A2 — Android Overlay Host & Onboarding
**Owns:** `android/**/overlay/`, `android/**/ui/`, `android/app/src/main/res/`, `AndroidManifest.xml` (coordinate with ORCH for any new permission).
**Build:**
1. `OverlayController` (interface already stubbed): creates the **FX window**, a full-screen `TYPE_ACCESSIBILITY_OVERLAY`, transparent WebView (`setBackgroundColor(0)`), flags `NOT_TOUCHABLE|NOT_FOCUSABLE|LAYOUT_IN_SCREEN|LAYOUT_NO_LIMITS`, `layoutInDisplayCutoutMode = ALWAYS`. Loads `file:///android_asset/overlay/index.html`. Sends `init`.
2. `SwarmBridge` `@JavascriptInterface post(json)`, dispatching on the main thread.
3. **Hit windows**: on `hitTargets`, create/move/remove small touchable `TYPE_ACCESSIBILITY_OVERLAY` windows (≥48dp, transparent) at each rect; a tap sends `window.swarm.dispatch({t:"tap", id})`. Add `{t:"tap"; id:string}` to the ToJs union through CHANGE_REQUESTS; ORCH pre-approves this. Recycle windows; update positions with `updateViewLayout` at most every 50ms.
4. **Panel mode**: on `panel{open:true}` remove `NOT_TOUCHABLE` from the FX window and hide hit windows; on close, restore.
5. Hide everything when Messages leaves the foreground (`hide`), and reappear on return.
6. `ActionExecutor` for `action` messages:
   - `report_7726`: `ACTION_SENDTO smsto:7726` with the original text prefilled (the user confirms the send).
   - `call_official`: `ACTION_DIAL tel:<payload.number>` (dial screen only, never auto-call).
   - `alert_guardian`: POST `/v1/guardian/alert`.
   - `block_sender`: be honest. Third-party apps can't block programmatically unless they're the default SMS/dialer app, so open the system blocked-numbers settings or a deep link, plus a toast explaining it.
   - `mark_safe`: local allowlist (in-memory plus DataStore, holding a salted hash of the sender only).
   - `dont_send` / `send_anyway`: forwarded to DraftGuard (Wave 3).
7. `MainActivity` onboarding (Compose or XML, keep it simple): 3 cards (What it does · What it reads, only Google Messages · What leaves your phone, with a sample privacy receipt). Button opens Accessibility settings. Guardian setup: name + phone, stored locally. Backend URL/key debug field.
8. `scripts/enable_service.sh` that enables the accessibility service via `adb shell settings`.

**Acceptance:** with A1 stubbed by a fake ScreenModel emitter (`DebugScreenFeed` that replays the S1 fixture), drones render over Google Messages, tapping a landed drone opens its panel, and scrolling Messages still works when the panel is closed (touches pass through).

### B — Overlay Web UI (drones)
**Owns:** `overlay/` only. Never needs the emulator.
**Build:**
1. Port visuals from `legacy/Signal_Swarm.html`: drone SVG with spinning rotors, scan beam, scanline sweep, verdict chips, tab panel, risk meter, the "Listen" speech walkthrough (Web Speech API). Restyle for a **phone portrait** viewport (360–412 CSS px wide) with Material-ish rounded panels that read clearly on top of Google Messages light and dark themes.
2. **Hive robot** dock bottom-right: idle bob; status ring green/amber/red; tap = open summary panel ("Swarm report").
3. State machine: `idle → scanning (drones launch from the Hive, all in parallel, fly to their anchors) → landed (each drone hovers 8px above its anchor rect and outlines it in its color) → panel`. On `localSafe`, Hive gives a soft green pulse "Checked on-device".
4. Anchor resolution: Finding.anchor → rect from the last `screen` message (`header`, bubble rect, link sub-rect if present, else bubble rect, `compose`). Re-anchor smoothly on every `screen` update (scroll). If an anchor is off-screen, the drone docks at the top or bottom edge with an arrow.
5. After landing or moving, post `hitTargets`. Post `panel` on open/close.
6. **Tab panel** (bottom sheet, max 70% height): tabs per drone with findings; each shows title, explanation, confidence as words + % ("Likely · 92%"; under 0.6 shows "Not sure" styling), evidence chips, "What would change my mind", action buttons (primary first). Extra tabs: **Summary** (verdict, category, risk), **Privacy receipt** (pretty-printed redacted payload + "Retained by server: no"), **Drift** sparkline when `riskSeries` is present (Wave 3).
7. Accessibility: panel content readable by TalkBack, 48dp targets, `prefers-reduced-motion` honored (reuse `T()` from the legacy code).
8. **Dev harness** `make overlay-dev`: serves `overlay/` with `dev/messages_bg.png` as a phone-frame background and replays `mock-feed.js` (screen → scanStarted → scanResult → scroll update). Buttons to load each fixture in `contracts/fixtures/`.
9. Playwright tests (`overlay/tests/`): load harness, play hero fixture, assert 4 drones landed within 2.5s, screenshots at landed and panel-open, no console errors. Verify `hitTargets` were posted (mock bridge records calls).
10. `make overlay-sync` copies `overlay/dist` into Android assets (build = plain copy unless you choose a bundler; keep it dependency-light).

**Acceptance:** Playwright passes; harness screenshots committed to `overlay/tests/screens/`.

### C — Detection Backend
**Owns:** `backend/` (except `mock_server.py` after Wave 0).
**Build:**
1. FastAPI app, Pydantic models imported from `contracts/models.py`. Middleware: API key check, **no request-body logging** (log requestId, latency, verdict only), CORS off.
2. **Classifier adapter** `classifier.py`: inspect `data/tmobile/` and wrap the provided baseline classifier behind `predict(text) → {category_id, label, prob}` mapped onto the T-Mobile taxonomy. If missing or unusable, train the fallback (TF-IDF + LogisticRegression on `data/synthetic/`) and set `source:"fallback"`. Document what you found in `backend/CLASSIFIER_NOTES.md`.
3. **Analyzers** (each a pure function `analyze(req, intel) → Finding | None` plus numeric features):
   - `sender.py` (Angler): kind, reputation hit (`data/reputation/numbers.csv`: complaint count, robocall flag, label), first-time sender (thread has no outgoing messages), brand-claimed-in-body vs non-short-code sender, email/alphanumeric senders, and the carrier gateway `FRM:` format.
   - `links.py` (Link): extract URLs (with or without scheme), punycode/IDN, homoglyph and edit-distance ≤2 vs brand domains in `data/domains.json`, shorteners list, risky TLDs, synthetic domain age lookup, path keywords. Anchor span = URL offsets.
   - `pressure.py` (Pressure): urgency/threat/secrecy/payment-rail lexicons with spans, plus classifier output.
   - `impersonation.py` (Impersonator): brand mention + mismatch signals → finding with an `call_official` action from `brands.json` (only entries with `verified:true`).
   - `attachments.py` (Carrier, P2 stub returns None).
4. **Ensemble** `ensemble.py`: features = classifier prob + analyzer scores → LogisticRegression trained on the training split from Agent E's split files, calibrated with `CalibratedClassifierCV` (isotonic if n>1000 else sigmoid). Persist to `backend/models/ensemble.joblib`. Map to verdict: ≥0.85 scam, ≥0.6 suspicious, 0.4–0.6 unsure, else safe. riskScore = round(100·p).
5. **Explainer** `explain.py`: for each finding, Claude (`LLM_MODEL`, default `claude-haiku-5-5`) gets ONLY the redacted text, the analyzer evidence and the category, and returns strict JSON `{title, explanation, whatWouldChangeMyMind}` per drone plus `summary`. Validate with Pydantic; on any failure or timeout (1.2s) fall back to **templates** (write good templates for every analyzer, since they're the default when offline). The LLM never changes severity, confidence, or verdict. Prompt rule: "Do not state facts not present in evidence."
6. **Actions builder**: scam/suspicious → `report_7726` (primary), `call_official` if a brand was matched, `alert_guardian`, `block_sender`, `delete`; unsure → `mark_safe`, `report_7726`; safe → none.
7. `/v1/guardian/alert` → forwards to photon `/internal/guardian-alert` (no message text in the payload, ever).
8. `/v1/feedback` → in-memory counters by verdict/label only.
9. Tests: pytest for each analyzer (≥8 cases each including legit look-alikes, e.g. real short-code bank alerts), API tests using the contract fixtures, a test asserting no log line contains request text, and a latency test without the LLM.

**Acceptance:** `make backend` on :8000; `curl` with `contracts/fixtures/scan_request_tmobile_lock.json` returns a schema-valid result with ≥4 findings in <150ms with `LLM_DISABLED=1`.

### D — Intel Data
**Owns:** `intel/`, `data/reputation/`, `data/brands.json`, `data/domains.json`.
**Build:**
1. `data/reputation/numbers.csv` columns: `e164,label,complaints,robocall,source,first_seen`. Sources:
   - **synthetic**: numbers used in our scenarios and the T-Mobile set (labelled by scenario).
   - **ftc_sample**: `intel/fetch_ftc.py` pulls recent FTC Do Not Call complaints from `https://api.ftc.gov/v0/dnc-complaints` (key `FTC_API_KEY`, default `DEMO_KEY`, respect rate limits), aggregates complaint counts and robocall share per number, and keeps the top N. Mark `source=ftc_unverified`; the UI must say "reported by consumers, unverified".
   - Never include personal numbers.
2. `data/brands.json`: `[{brand, aliases[], domains[], shortCodes[], officialPhone, officialUrl, verified, sourceUrl}]` for ~15 brands commonly impersonated (T-Mobile, USPS, UPS, FedEx, Amazon, Apple, Chase, Bank of America, Wells Fargo, PayPal, Venmo, Zelle, IRS, E-ZPass/toll agencies, Netflix). **Only set `verified:true` for numbers/domains you confirmed on the brand's official site, and record `sourceUrl`.** T-Mobile: 611 from a T-Mobile phone.
3. `data/domains.json`: brand domain list (for lookalike checks), shortener list, risky TLD list, and a **synthetic WHOIS table** `{domain, createdDaysAgo}` for every scam domain in the scenarios.
4. `intel/build_bundle.py` → `/v1/reputation/bundle` content (salted SHA-256 of E.164) for P1 on-device lookup.
5. `intel/README.md`: provenance of every file.

**Acceptance:** schemas validated by `intel/test_intel.py`; every scenario sender/domain resolvable in the data.

### E — Scenarios, Injector, Eval
**Owns:** `scenarios/`, `scripts/inject.py`, `scripts/e2e.sh`, `eval/`, `data/synthetic/`.
**Build:**
1. Scenario YAML format:
   ```yaml
   id: tmobile_account_lock
   sender: "4695550182"
   steps:
     - {delay: 0, text: "T-Mobile: your line will be suspended in 2 hrs. Verify: t-mobi1e-acct-verify.co/a8f"}
   expect: {verdict: scam, drones: [angler, link, pressure, impersonator]}
   ```
   Optional `user_reply` steps are printed as cues for the presenter (we can't type into Messages from adb reliably; if `adb shell input text` works, support `type:` steps).
2. Write ≥20 scenarios covering the T-Mobile taxonomy, including the demo set: `tmobile_account_lock`, `toll_unpaid` (E-ZPass style), `usps_redelivery`, `otp_harvest` (2 senders: scammer long code + legit short-code OTP), `grandkid_giftcards`, `wrong_number_crypto` (6 steps, 5s apart), `job_offer_whatsapp`, `bank_fraud_alert_callback`, `irs_threat`, `prize_winner`, **and ≥5 legit look-alikes** (real-style short-code bank alert with no link, pharmacy pickup, 2FA code with no request, a friend sharing a link, a delivery notice from a short code). Scam domains must not resolve (`dig +short` empty; script checks).
3. `scripts/inject.py <scenario>`: uses `adb emu sms send <sender> "<text>"` with delays and proper shell escaping; `--call <number>` uses `adb emu gsm call`. `make inject S=<id>`.
4. `scripts/e2e.sh <scenario>`: clear logcat → inject → open thread (`adb shell am start` with an `sms:` intent, or tap via uiautomator) → wait for `scan_complete` in `adb logcat -s SWARM` → screencap to `eval/screens/<id>.png` → compare verdict vs `expect`.
5. **Dataset + splits**: normalize the T-Mobile set (or a generated stand-in if absent) into `data/synthetic/all.jsonl` `{id,text,sender,label,category}`; deterministic 70/15/15 split files. Agent C trains only on train/val.
6. `eval/run_eval.py`: runs baseline classifier vs full swarm (call `/v1/scan` in-process) on the **test split** → `eval/report.md` + `eval/report.json`: accuracy, per-category P/R/F1, **false-positive rate on legit**, ECE + reliability diagram PNG, latency p50/p95, and the 10 worst errors (IDs only). Include a `--thread` mode for multi-turn scenarios measuring drift detection turn index.

**Acceptance:** `make eval` produces the report against the mock (Wave 1) and the real backend (Wave 2+).

### F — Photon Service
**Owns:** `photon/`.
**Build:**
1. Read Photon docs first: `https://photon.codes/docs/llms-full.txt`, the Spectrum getting-started page, the **2.0 beta** "Build an iMessage agent" page, the SMS and webhook pages, plus `docs/photon-guidelines.md` if the human added it. Summarize the APIs you'll use in `photon/PHOTON_NOTES.md` (what's stable vs beta, auth, inbound mode, rate limits, app cards).
2. Bun + TypeScript + Photon SDK. Start on Photon's **terminal provider** so it works before keys arrive; switch to iMessage/SMS via env `PHOTON_PROVIDER`.
3. **Forward-to-Swarm line**: on an inbound message → TS port of the redactor (share the test table with A1 via `contracts/fixtures/redaction_cases.json`; ORCH creates it) → `POST /v1/scan` with `client:"photon"` → reply:
   - Line 1: verdict + risk ("🚨 Likely scam · 92% sure")
   - Up to 3 drone findings, one line each, prefixed with the drone name
   - Next steps (report to 7726, call the official number)
   - If Photon app cards are available on the channel, send a card with the same content plus buttons; else plain text.
   - Commands: `HELP`, `PRIVACY` (explains what's stored: nothing), `STOP`.
4. **Guardian alerts**: `POST /internal/guardian-alert` (auth `X-Swarm-Key`) → send "Signal Swarm stopped a likely {categoryLabel} scam on {userAlias}'s phone (risk {riskScore}). No message content was shared. Reply CALL to call them." Handle replies `CALL` (respond with a tel: link) and `OK`.
5. Verify Photon webhook signatures (Standard Webhooks) if using webhooks. Secrets from `.env` only.
6. Tests: unit tests for reply formatting and redaction parity; a terminal-provider smoke script `bun run demo:terminal`.

**Acceptance:** in terminal mode, pasting the hero scam text returns the formatted verdict from the real or mock backend; `curl` to `/internal/guardian-alert` prints/sends the alert.

---

## 9. Wave 2 — Integration (Orchestrator + fresh QA agent)

1. Merge in order C → D → E → B → A1 → A2 → F, running `make check` after each (contract tests + backend pytest + overlay Playwright + Android unit tests + photon tests).
2. `make overlay-sync && make android` → install → `scripts/enable_service.sh` → `adb reverse tcp:8000 tcp:8000` → `make backend`.
3. Run `scripts/e2e.sh tmobile_account_lock` until green. Fix integration bugs yourself (small) or send them back to the owning agent (big).
4. Spawn a **fresh QA agent** (no prior context) with: "Follow §2 steps 1–2 of PLAN.md exactly on the emulator, try to break it (scroll during scan, rotate, background the app, inject 3 messages quickly, open a legit thread), file issues in `QA.md` with repro steps and screenshots."
5. Triage `QA.md` → assign fixes into Wave 3 agents' prompts.

**Exit criteria:** hero scenario green 3 runs in a row; legit bank scenario shows no drones (local safe or verdict safe); touches pass through to Messages when the panel is closed.

---

## 10. Wave 3 — P1 features (six parallel agents)

| Agent | Feature | Spec |
|---|---|---|
| **A1 → Warden** | Pre-send guard | `guard/DraftGuard.kt`: on `typeViewTextChanged` in the compose node, run on-device detectors (OTP code typed while the thread or a recent thread contains a code request; gift-card patterns with brand words; Luhn card numbers; SSN; the word "password" + text). Debounce 300ms. On a hit, build a local `ScanResult` with a `warden` finding (anchor `compose`, actions `dont_send` primary, `send_anyway`) and emit `draftRisk`; optionally enrich via `/v1/scan mode:"outgoing_draft"` with the **draft redacted** (the code replaced by `<CODE:n>`). Intercept: A2 places a touchable hit window over the `send` rect while the risk is active; `send_anyway` → `performAction(ACTION_CLICK)` on the real send node; `dont_send` → `ACTION_SET_TEXT ""` on the compose node. Unit tests for the detectors. |
| **A2 → Calls** | Incoming-call drone | `calls/SwarmCallScreeningService`; request `ROLE_CALL_SCREENING` via RoleManager in onboarding. `onScreenCall` → local reputation lookup (bundle hashes) → if risky, `respondToCall` with `setSilenceCall(true)` only (never auto-reject in the demo) and emit `incomingCall` so the Impersonator drone pops over the incoming-call UI with the complaint count + "reported by consumers, unverified". Demo with `make inject S=robocall` (`adb emu gsm call`). |
| **B → Polish** | Drift + receipt + motion polish | Drift sparkline tab; Warden compose-box dive animation and "Hold up" card; incoming-call layout; Privacy receipt tab; light/dark contrast pass over both Messages themes; reduced-motion; final Playwright screenshots. |
| **C → Drift & calibration** | Thread trajectory + accuracy | `analyzers/drift.py`: per-message stage tagging (rapport, trust, off-platform, money, urgency) via lexicons + classifier → `riskSeries` + a `drift` finding when the slope crosses a threshold or the stage reaches money/off-platform. Retrain the ensemble with drift features; tune thresholds on **val** to minimize legit FPR at ≥90% scam recall; rerun `make eval`. |
| **F → Guardian polish** | Photon app card + two-way | App card for verdicts if supported; guardian `CALL`/`OK` handling; the "Alert my guardian" path end-to-end from the Android action through backend → photon → real phone (needs H3/H5). Record a screen capture of the phone receiving it. |
| **H → Pitch** | Story + assets | `pitch/deck.md` (or slides): problem stat, demo flow, architecture, privacy-by-design (on-device prefilter, redaction, no retention, scoped accessibility, privacy receipt), honest confidence, eval table vs baseline, Photon use, future (carrier-level integration, on-device model, RCS). `pitch/demo_script.md` timing to 3:00. `README.md` with setup + judging map (§13). |

---

## 11. Wave 4 — Freeze & demo

1. Feature freeze. Only bug fixes.
2. Fresh QA agent runs the full §2 script twice and every scenario via `scripts/e2e.sh --all`; results in `QA.md`.
3. `make eval` on the final backend → copy numbers into the pitch.
4. **Record the backup demo video** of the full §2 flow (emulator screen + the guardian phone). Commit to `pitch/`.
5. Demo-day checklist in `pitch/checklist.md`: emulator cold-boot snapshot saved with the app installed and service enabled; `adb reverse` run; backend up; `LLM_DISABLED=1` fallback rehearsed in case the Wi-Fi is bad; scenario commands on a cheat sheet.

### Compressed plan (≤ 8 hours left)
- Wave 0 as written (ORCH + S1).
- Wave 1 with **A1, A2, B, C, E** only. D shrinks to whatever C/E need inline. F runs only if Photon keys exist, building the guardian alert alone (no forwarding line).
- Skip Wave 3 except **Warden** (A1+B), since it's the most novel feature. Skip calls, drift, and app cards.
- Wave 4: QA once, record video, eval report.

---

## 12. Cross-cutting requirements (every agent)

**Privacy & security**
- No real customer data. Synthetic only.
- The accessibility service is scoped to the Google Messages package; the config XML lists only it.
- On-device prefilter first; redaction before any network call; the exact outgoing payload is shown in the Privacy receipt.
- Thread buffer RAM-only; allowlist stores salted hashes only.
- Backend and photon never log message text. A test enforces it.
- No server-side retention; `privacy.retained=false` must be true.
- Guardian alerts contain category + risk only, never message content.
- Secrets only in `.env` (gitignored). `X-Swarm-Key` on all internal calls; Photon webhook signatures verified.
- Actions never act silently: dialing opens the dialer, reporting opens a prefilled SMS to 7726, blocking explains its limits.

**Honest confidence**
- Confidence shown as words + %, from the calibrated ensemble. Under 0.6 renders as "Not sure" and always includes `whatWouldChangeMyMind`.
- FTC reputation is labelled "reported by consumers, unverified".
- Template fallbacks exist for every explanation; the demo must work with `LLM_DISABLED=1`.

**Engineering**
- Every agent: tests for its own code, `make check` green before reporting, final report in the format of §6.
- Don't add heavy dependencies without a reason in the report.
- Keep the overlay smooth: 60fps target, cap `updateViewLayout` frequency, debounce accessibility events.

---

## 13. Judging map (put in README and pitch)

| T-Mobile criterion | Where we hit it |
|---|---|
| Creativity | Drones that physically fly to the risky part of a real messaging app; pre-send Warden; thread drift; guardian alerts |
| Impact | Works on the default Messages app with no switching; covers iPhone via Photon; protects family members |
| Usability | One glance (Hive color), one tap (drone tab), one action (report/call real/alert guardian); plain-language and TTS |
| Security & privacy | On-device prefilter, redaction, privacy receipt, no retention, scoped accessibility, content-free guardian alerts |
| Detection accuracy | T-Mobile baseline + analyzers + calibrated ensemble; eval report with per-category F1, legit FPR, calibration |
| "Go beyond classification" | Safeguards (Warden intercept, call silencing), next steps, education via explanations |
| Photon | Forward-to-Swarm iMessage/SMS line + guardian alerts (+ app cards) |

---

## 14. Copy-paste prompts

### For the Orchestrator (Claude Code)
> Read `PLAN.md` fully. You are the Orchestrator. Execute Wave 0 now: do the ORCH tasks yourself and, in the same message, launch the S1 spike agent in parallel (worktree isolation). When both finish, tag `contracts-v1` and launch **all seven Wave 1 agents in a single message** (A1, A2, B, C, D, E, F), each with worktree isolation and its prompt built from the template below plus its section of §8. While they run, do nothing that touches their directories. When all report back, run Wave 2 per §9, then Wave 3 per §10 (launch all six in one message), then Wave 4. Keep `STATUS.md` updated after every wave with done / blocked / next.

### For Codex
> Read `PLAN.md`. Do Wave 0 (§7 ORCH tasks) in this task and push branch `main` with tag `contracts-v1`. Then create one Codex task per Wave 1 workstream (§8), each on branch `ws/<id>`, using the template prompt in §14. Android tasks (S1, A1, A2) must run locally where the emulator and adb are available.

### Workstream agent template
> You are agent **{ID} — {NAME}** on the Signal Swarm project. Read `PLAN.md` §3, §5 (contracts, read-only), §12, and your section **{SECTION}**. You own only: **{DIRS}**. Do not edit other directories; if you need a contract change, append it to `contracts/CHANGE_REQUESTS.md` and continue with a local shim. Build against mocks/fixtures (`make mock`, `contracts/fixtures/`) so you never wait on other agents. Write tests for your code and run `make check` before finishing. Never log message text; synthetic data only. Finish with a report: (1) what's done, (2) how to run it, (3) tests run and results, (4) known issues, (5) requests for other agents/ORCH.

---

## 15. Command cheat sheet

```bash
# emulator & app
emulator -avd Pixel_8_API_35 &
adb reverse tcp:8000 tcp:8000
make overlay-sync && make android        # ./gradlew installDebug
scripts/enable_service.sh                # adb shell settings put secure enabled_accessibility_services <pkg>/<svc>; accessibility_enabled 1

# synthetic traffic
adb emu sms send 4695550182 "T-Mobile: your line will be suspended in 2 hrs. Verify: t-mobi1e-acct-verify.co/a8f"
adb emu gsm call 8885550199
make inject S=wrong_number_crypto

# debugging
adb logcat -s SWARM
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml

# services
make mock          # fixture backend :8000
make backend       # real backend :8000
cd photon && bun run dev
make eval
make check
```

## 16. Risk register

| Risk | Likelihood | Mitigation / fallback |
|---|---|---|
| Google Messages tree hard to parse | Med | S1 spike first; parser uses text + geometry heuristics; fixture tests. Fallback: drones anchor to whole bubbles only (no link sub-rects). |
| Touch passthrough issues | Med | TYPE_ACCESSIBILITY_OVERLAY + hit windows; Panel mode flip. Fallback: drones are non-interactive, and tapping the Hive opens the panel. |
| Email/alphanumeric sender not injectable | High | Carrier gateway `FRM:` body format parsed by Angler; show the email case via the Photon line instead. |
| T-Mobile classifier format awkward | Med | Adapter + fallback classifier; document in CLASSIFIER_NOTES.md. |
| Photon 2.0 beta API changes / keys late | Med | Terminal provider first; guardian alert is the minimum Photon deliverable. |
| LLM latency/outage at demo | Med | Templates by default under 1.2s timeout; rehearse with `LLM_DISABLED=1`. |
| Venue Wi-Fi | Med | Everything local except LLM + Photon; recorded backup video. |
| Accessibility permission seen as invasive | Med | Privacy story (§12), onboarding transparency, scoped package, privacy receipt; pitch notes a production path through carrier/system integration. |
