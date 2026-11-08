# Intel data provenance
All data is synthetic or public knowledge. No personal numbers.
- `data/brands.json`: ~15 commonly impersonated brands (aliases, official domains). `verified:true` only for T-Mobile (611 from a T-Mobile phone); every other brand is `verified:false`, so the backend never emits a `call_official` action for them. Domains are public; short codes other than 611 are intentionally left empty (not confirmed).
- `data/domains.json`: brand domains (lookalike checks), shorteners, risky TLDs, path keywords, common TLDs, and a **synthetic WHOIS** table (`createdDaysAgo` is fabricated for demo scam domains, e.g. t-mobi1e-acct-verify.co = 3 days).
- `data/reputation/numbers.csv`: synthetic numbers (555-01xx style) labelled by scenario. No live FTC fetch is included (`intel/fetch_ftc.py` skipped); if added, rows must be `source=ftc_unverified` and shown as "reported by consumers, unverified".
- `intel/build_bundle.py`: salted SHA-256(salt+e164) bundle for `/v1/reputation/bundle` (salt via `REPUTATION_SALT`).
- Tests: `python -m pytest -q intel`.
