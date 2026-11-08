# Photon notes (docs read: photon.codes/docs/llms-full.txt, Stable)
- SDK: `spectrum-ts` (Stable). Beta docs live under /docs/beta/; NOT used. Per-provider pkgs exist (`@spectrum-ts/imessage`), framework webhook adapters (`@spectrum-ts/hono|express|elysia`).
- Auth: `Spectrum({projectId, projectSecret, providers})` or env `SPECTRUM_PROJECT_ID/SECRET`. Projectless `terminal` provider needs nothing. We read `PHOTON_PROJECT_ID/SECRET` from `.env`.
- Providers in docs: iMessage, WhatsApp Business, Telegram, Terminal, Voice. No documented Spectrum SMS provider (SMS runs on Photon numbers via Telnyx, but no SDK page found).
- Inbound: stream (`for await [space,message] of app.messages`) - what we use; or `app.webhook()` (HMAC-SHA256 over `v0:<ts>:<rawBody>`, 5 min replay window, secret `webhookSecret`/`SPECTRUM_WEBHOOK_SECRET`, at-least-once delivery -> dedupe on message.id). We do not use webhooks, so no signature code.
- Outbound: `space.send(text)`; new DM: `im = imessage(app); im.space.create(await im.user(phone))`.
- App cards: `app(url)` is only a tappable URL card (no buttons/body), so replies are plain text.
- Our switch: `PHOTON_PROVIDER=terminal|imessage` (src/provider.ts). Terminal mode is a local readline loop with the same interface; the Spectrum path is untested without credentials.
