# PitCrew field design

The entire frontend uses black (`#080809`), ghost white (`#f8f8ff`), and neutral grays. Light mode reverses those roles. Status is communicated with explicit labels, icons, border weight, and pattern rather than hue. HOLD remains a disabled safety gate; changing the palette does not change any plant decisions, authentication, integrations, or state contracts.

The identity is a custom SVG survey mark: stacked planes around a fixed reference point. Its geometry is repeated in the static, low-contrast survey grid behind the foreground. The wordmark, sign-in/loading states, footer, message mirror, favicon, and PWA icon all use this mark. Standalone assets are `apps/field/public/logo.svg`, `icon.svg`, and `survey-grid.svg`; the theme-aware inline version is `components/brand-mark.tsx`.

## Page coverage

| Workspace | Treatment |
| --- | --- |
| My shift | Three-phase shift journey, inherited handover, one next inspection, and ongoing commitments. |
| Start my shift | Incoming I-PASS items and read-backs with a durable receipt. |
| Work my rounds | Risk-ordered walking route, recorded-stop status, and one next inspection. |
| Guided inspection | Evidence, observed reading, field observation, ownership, and a server-validated inspection record. |
| Equipment | Search, aligned reading/tag columns, explicit no-match state, divided equipment rows. |
| Equipment record | Equipment identity pass, large current reading and baseline chart, field-note entries, related procedures and source context. |
| Warnings | Ownership/action card beside an evidence and escalation column; severity remains explicit in text. |
| Shift handover | I-PASS entries, confirmation progress, recorded read-backs, and send action. |
| Procedures | Procedure library, source-PDF compiler, step progress, selected equipment, and explicit GO/HOLD decision. |
| Incident response | Projected time, correlated alarms, assumptions, emergency procedure, and response contacts. |
| Demo Director | Reset in the page header; clock/cache controls precede the scenario collection; audit log below. |
| Decision traces | Decision count, summaries and plans, expandable tool inputs/results. |
| Message mirror | Monochrome conversation workspace, provider/status labels, read and ownership actions. |
| Power topology | Source-to-load diagram with explicit protected/bypass states and equipment links. |
| Equipment tags | High-contrast QR cards, asset identities, current-host URLs, and print layout. |
| Sign-in / loading / dialogs | New mark and monochrome surfaces; existing authentication and input flows retained. |

The technician navigation centers on My shift, Work rounds, and Handover, with supporting equipment and procedures. A mobile reference rail keeps equipment, procedures, messages, and tags accessible. Presenter controls and full agent traces live under the direct `/presenter` entry point and are absent from technician navigation. See [task-led experience](task-led-experience.md) for the route map, completion guarantees, and inspected ClickUp/Trello/Lemonade references.

## Motion and access

Framer Motion handles page entrances (180ms), shared navigation selection (180ms), dialog/backdrop entrances and exits (200–250ms), toast feedback (200ms), and handover confirmation layout/progress (200ms). Entrances use `cubic-bezier(0.23, 1, 0.32, 1)` and only transform/opacity; the progress bar scales from its left edge. Readings and charts do not move continuously. The background is static.

Reduced-motion preferences remove movement and shorten fades. Hover feedback is restricted to devices with a fine pointer. Inputs remain at least 16px on mobile. Dialogs trap Tab focus, dismiss on Escape, restore their trigger's focus, and prevent background scrolling. Errors, empty states, blocked actions, and simulated-provider labels remain visible.

## References and implementation

The work-list and context-column structure draws on inspected [Plane](https://mobbin.com/screens/7e08d076-9297-4567-99d6-2e3a8c6dab3e) and [incident.io](https://mobbin.com/screens/5ef4cdae-21ec-45a6-9922-eec0854b44ff) screens. [Quo](https://mobbin.com/screens/58ece968-d3e6-48b4-a975-912ddde3d491) informed workspace navigation and page action placement. The earlier [Apple Health metric detail](https://mobbin.com/screens/f6471b67-8921-4d71-826b-476849a1ec61) reference informed the reading/baseline/chart relationship. These are structural references; the requested monochrome palette, custom vector identity, page treatments, and motion are PitCrew's implementation.

No UI dependency was added. `globals.css` retains foundational component rules with legacy colors converted to neutrals; `workspace.css` defines the monochrome system; `task-flow.css` defines the shift and guided-inspection layouts. Inspection-stage transitions use a short 160ms fade/translation and honor reduced motion.

`scripts/verify-task-flow.ts` exercises the frontend with an isolated in-memory PlantStore, intercepted API calls, and a browser-local event stream. It does not load credentials, write the running database, or send live communications. It covers desktop/phone widths, the complete guided inspection, reload persistence, light/reduced motion, and the S2 HOLD. Captures are written to ignored `tmp/task-flow/`. The older `redesign-preview.ts` command forwards to this verifier on the task-led branch; its original implementation remains on `master`. Browser emulation does not replace physical-device Safari, camera, or microphone testing.
