# Signal Swarm conventions
Source of truth: PLAN.md, with one change: the app is **Flutter** (see contracts/BRIDGE.md). Overlay UI, redactor, prefilter, scan client, DraftGuard = Dart in `app/lib`; Kotlin in `app/android` only reads Google Messages (AccessibilityService), manages overlay windows, runs intents.
## Ownership (edit only your dirs)
- android-native: app/android/**  | dart-core: app/lib/core/**, app/test/core/** | overlay-ui: app/lib/overlay/**, app/test/overlay/**
- app-shell: app/lib/main.dart, app/lib/ui/** | backend: backend/** | intel: intel/**, data/** (except synthetic) | eval: scenarios/**, eval/**, scripts/**, data/synthetic/** | photon: photon/**
- contracts/** is orchestrator-only. Needs a change -> append to contracts/CHANGE_REQUESTS.md.
## Rules
Synthetic data only. Never log message text. Redact before any network call. Template explanations must work with LLM_DISABLED=1. Run your own tests before reporting.
Env: PATH needs /c/Users/moham/flutter/bin. Backend python: `python -m uvicorn`. Emulator reaches host via `adb reverse tcp:8000 tcp:8000`.
