# Signal Swarm conventions
Source of truth: PLAN.md, with one change: the app is **Flutter** (see contracts/BRIDGE.md). Overlay UI, redactor, prefilter, scan client, DraftGuard = Dart in `lib`; Kotlin in `android` only reads Google Messages (AccessibilityService), manages overlay windows, runs intents.
Swat integration: the single Flutter app is at the repository root. Preserve Swat's account, theme, inbox, email, voice and Family flows; use its artwork and palette. PLAN.md and contracts/BRIDGE.md contain historical app/ paths that now resolve at the root.
## Ownership (edit only your dirs)
- android-native: android/**  | dart-core: lib/core/**, test/core/** | overlay-ui: lib/overlay/**, test/overlay/**
- app-shell: lib/main.dart, lib/ui/**, lib/screens/**, lib/services/**, lib/widgets/**, lib/models/**, lib/theme/**, lib/data/** | backend: backend/** | intel: intel/**, data/** (except synthetic) | eval: scenarios/**, eval/**, scripts/**, data/synthetic/** | photon: photon/**
- contracts/** is orchestrator-only. Needs a change -> append to contracts/CHANGE_REQUESTS.md.
## Rules
Synthetic data only. Never log message text. Redact before any network call. Template explanations must work with LLM_DISABLED=1. Run your own tests before reporting.
Env: PATH needs /c/Users/moham/flutter/bin. Backend python: `python -m uvicorn`. Emulator reaches host via `adb reverse tcp:8000 tcp:8000`.
