# Google Messages UI notes (S1 spike)

Emulator: Pixel-class API 36, 1080x2400 @420dpi, Google Messages (com.google.android.apps.messaging), "Use Messages without an account", Messages is the default SMS app. Dumps via `scripts/dump_ui.sh out.xml` (uiautomator). Fixtures: `app/android/app/src/test/resources/fixtures/*.xml`.

NOTE: the live AccessibilityService tree has not yet been compared with uiautomator (APK build blocked, see report); the uiautomator tree is the same tree plus `visible-to-user` filtering.

## Key finding: the thread screen is Jetpack Compose
Most nodes have a Compose `testTag` as `resource-id` (`message_list`, `message_text`, `Compose:Draft:Send`, `ComposeRowIcon:*`), not an `android:id`. Only the compose EditText and the conversation list use real ids. Tags are stable across the runs we did but are not a public contract, so the parser keys off text and content-description first.

## Conversation list (`conversation_list*.xml`)
RecyclerView `android:id/list` (desc "Conversation list"); per row `conversation_name`, `conversation_snippet` (outgoing snippets start with `You:  `), `conversation_timestamp`, unread badge TextView (just a digit). No `message_list`, no EditText => parser returns `inThread=false`.

## Thread (`thread_one_incoming.xml`, `thread_mixed.xml`, `thread_scrolled.xml`)
- Scroll container: `resource-id="message_list"`, scrollable, bounds start at y=63 (runs under the app bar).
- **Bubble = `android.widget.TextView`, resource-id `message_text`.** `text` is the body; for outgoing bubbles the text has a leading space (`" ok no code 3"`).
- **Direction: `content-desc` is `"<sender> said  <body> <time> ."` for incoming and `"You said   <body> <time> ."` for outgoing.** Stable and locale-text based. Fallback if the desc is empty: geometry. Incoming bubbles are left-aligned (x starts ~63), outgoing right-aligned (ends x=1017, starts >~700); centered nodes are banners.
- The bubble TextView bounds cover the text only (x 63..924 for incoming wrapped text). The visual bubble is ~24px wider on each side and ~12px taller; the parser inflates by that. Link-preview cards (`LinkPreviewContent`, "Tap to load preview") are sibling views, not part of the bubble node.
- Non-bubble `message_text` nodes (empty desc, centered): "Link previews are on...", "Texting with <sender> (SMS/MMS)". Date separators ("2:17 AM") are plain TextViews with no resource id. "Unread" divider likewise.
- Hierarchy order is NOT visual order and includes the previous/next items; sort by `bounds.top`. Nodes clipped by scrolling keep clipped bounds (e.g. a bubble at `[63,63][924,95]` under the app bar). uiautomator omits fully off-screen nodes.
- There are no per-URL nodes: links are underlined spans inside the same TextView. Link rects are estimated (greedy wrap with uniform char width) => best-effort, a few tens of px off.
- Message ids: none. Use sha1(threadKey + text + ordinal).

## Header / sender
App bar: Back (`desc "Back"`), avatar (`GlideMonogram`), **title TextView with the sender text** (no id; first TextView with top in 40..260 left of the call buttons; bounds y~116..179), then `Call`, `Make a video call`, `More`. Below it, for unknown senders, a card with "Save (469) 555-0182?", "Report spam", "Add contact" (excluded from the header search; also useful as a first-time-sender signal).
Sender display formats: long code `(469) 555-0182`, toll-free `(888) 555-0100`, short code `62884`/`22000` unchanged, alphanumeric `T-Mobile` unchanged. Contacts would show names (not testable here).

## Compose box
- `android.widget.EditText`, `resource-id="com.google.android.apps.messaging:id/compose_message_text"` (real id), bounds ~[316,2190][796,2316] without keyboard (moves up with the IME, e.g. y=1370).
- Empty state: `text="Text message"` which is the HINT shown as text. Live API: `isShowingHintText` is true; parser also treats `^(Text|RCS|Chat)? message$` as empty.
- Typed: `text` = typed text (`thread_draft_typed.xml`). Note the emulator `input text` mangled "?" to "%3F"; irrelevant to the real app.
- **Send button exists only while there is a draft**: clickable `View` with `resource-id="Compose:Draft:Send"`, child desc `"Send SMS"` (or "Send RCS"...). bounds ~[923,1371][1049,1497]. When empty the voice-record icon (`ComposeRowIcon:Voice`) takes that spot.
- **Threads from alphanumeric senders and short codes have no compose box**: text "Can't reply to this short code. Learn more" (`thread_alphanumeric_no_compose.xml`). Warden does not apply there. Real short codes (62884, 22000) kept a compose box in our test.

## Stability without resource ids
| Signal | Stable? |
|---|---|
| `content-desc` "X said ..." / "You said ..." | Good (text pattern, English locale; geometry fallback) |
| Bubble class TextView + non-empty text | Good |
| `message_text` / `message_list` / `Compose:Draft:Send` tags | Good today, Compose testTags, may change with app updates |
| `compose_message_text` EditText id | Good (real id); fallback any EditText |
| Header = TextView in top band | Good (geometry) |
| Link sub-rects | Estimated only |

## Sender format injection results (`adb emu sms send`)
| Sender | Result |
|---|---|
| `4695550182` | works, displayed `(469) 555-0182` |
| `62884`, `22000` (short code) | works, thread keeps a compose box |
| `8885550100` (toll-free) | works, `(888) 555-0100` |
| `T-Mobile` (alphanumeric) | works, no compose box ("Can't reply") |
| `alerts@t-mobi1e-support.co` (email) | **fails as a sender**: conversation row has an empty name; body arrives. Fallback per plan: scenarios use the gateway body format `FRM:alerts@... MSG:...`; Angler parses it (confirmed that the body displays verbatim) |
| `adb emu gsm call 8885550199` | works: heads-up "Incoming call" notification when unlocked (`(888) 555-0199`, Decline/Answer), full-screen when locked. `adb emu gsm cancel 8885550199` hangs up |

## Go / no-go
| Risk | Verdict |
|---|---|
| Read bubble text + in/out from a11y tree | GO (content-desc + geometry) |
| Bubble bounds for drone anchoring | GO (inflate text bounds; clipped by scroll, parser drops <50% visible) |
| Link sub-rects | PARTIAL: estimated; fallback to whole-bubble anchor |
| Sender from header | GO |
| Compose text + send node | GO while a draft exists; send node absent when empty; no compose on alphanumeric threads |
| Email sender injection | NO-GO via adb; use gateway body format |
| Incoming call injection | GO |
| Leaving-Messages detection | The service is package-scoped, so no events arrive after leaving; the service polls `rootInActiveWindow.packageName` every 700ms while visible (to verify live) |
| Dark theme fixtures | not captured |
| Tests share the emulator with other agents; extra threads (22000 CVS) in the list came from another agent's injection | note |
