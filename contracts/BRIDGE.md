# Native <-> Dart bridge (replaces the WebView bridge in PLAN §5.3; message shapes unchanged)
MethodChannel `swarm/bridge` (both directions), arguments = JSON string of the §5.3 union.
Kotlin -> Dart: init, screen, hide, tap, draftText {text}, action results. Dart -> Kotlin: ready, hitTargets, panel, action, log.
The overlay engine (entrypoint `overlayMain` in app/lib/main.dart) runs inside the accessibility service process.
Dart does redaction, prefilter, ThreadBuffer, ScanClient and DraftGuard (app/lib/core); Kotlin only reads/parses the screen and manages windows + intents.
Screen rects are SCREEN PX; Dart divides by devicePixelRatio. Fixture: fixtures/bridge_screen_example.json.

## Addendum: screen message carries text
screen = { t:"screen", visible, threadKey, senderRaw, draftText, header, compose, send, bubbles:[{messageId, direction, text, rect, linkRects}] }
Kotlin parses text on-device and sends it only to the in-process Dart engine; Dart redacts before any network call. messageId = sha1(threadKey+text+ordinal) from Kotlin.
Dart->Kotlin channel methods: ready, hitTargets({targets:[{id,rect}]}), panel({open}), action({id,payload,requestId}), log.
Kotlin->Dart channel methods: init({density,screenW,screenH,insets}), screen(json), hide, tap({id}).
Dart classes: app/lib/contracts.dart.
