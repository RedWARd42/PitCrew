# Contract change requests

## Local report handoff (2026-11-08)

Document the new app-local `swat/reports` channel: overlay `openReport({reportId})`
launches MainActivity with a validated opaque SHA-256 ID; activity
`takePendingReport()` consumes it and `reportAvailable` notifies a running app.
`openSource({channel: sms|email})` opens an allowlisted source package. Reports
stay in app-private preferences; intents never carry message text or scan bodies.
The existing swarm/bridge and backend wire schemas are unchanged.

## Swat root-app migration (2026-11-08)

Update the historical paths in BRIDGE.md from app/lib and app/android to lib and android. The Android application ID is now com.example.signal_swarm, preserving Swat main. Bridge names, payloads and wire schemas are unchanged.
