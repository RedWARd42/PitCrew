# Solana — community blocklist anchor

**[MLH] Best Use of Solana.** Swat's shared blocklist (MongoDB
Atlas, `../backend/`) is mirrored to **Solana devnet** as Memo
transactions, so the list becomes publicly verifiable without
trusting our server:

- Each block anchors `SWAT1|<sha256(sender)>|<risk>|<incidentId>`.
- Only a **fingerprint** goes on-chain — the raw phone number never
  leaves the device/server, and formatting differences
  (`+1 (872) 555-0147` vs `18725550147`) fingerprint identically.
- Anyone can fingerprint a sender locally and search devnet for a
  matching anchor to confirm the fleet convicted it.

## Run it (devnet)

```sh
cd solana
npm install
solana-keygen new -o devnet-wallet.json        # or any keypair JSON
# fund it: https://faucet.solana.com (devnet, free)
SOLANA_KEYPAIR_PATH=./devnet-wallet.json npm run anchor -- +1-872-555-0147 100 INC-2026-1234
```

Without `SOLANA_KEYPAIR_PATH` the script prints the payload and the
exact steps instead of anchoring — no fake transactions.

## Scope, honestly

This is a devnet prototype: anchoring is a batch/manual step beside
the backend, not yet wired into `POST /reports`, and mainnet use
would need a funded wallet and a fees policy. The fingerprint design
is the point — a public, tamper-evident threat-intel list that never
publishes a phone number.
