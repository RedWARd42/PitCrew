// Community blocklist anchor — [MLH] Best Use of Solana.
//
// The fleet backend's blocklist lives in MongoDB Atlas; this anchors
// it to Solana devnet so the list is publicly verifiable without
// trusting our server: each block becomes a Memo transaction carrying
// only a SHA-256 fingerprint of the sender (never the raw number),
// the risk score, and the incident id. Anyone can fingerprint a
// sender locally and check whether the fleet has convicted it.
//
//   node anchor.mjs +1-872-555-0147 100 INC-2026-1234
//
// Wallet: SOLANA_KEYPAIR_PATH points at a devnet keypair JSON
// (solana-keygen new + a faucet airdrop). Without one, an ephemeral
// keypair is generated and the anchor is skipped with instructions —
// devnet only, by design; see README.md.

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

export const MEMO_PROGRAM_ID = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';

/// Digits only, country-code normalized: formatting never changes
/// the fingerprint, so "+1 (872) 555-0147" and "18725550147" match.
export function normalizeSender(sender) {
  return String(sender).replace(/\D/g, '');
}

export function fingerprintSender(sender) {
  return createHash('sha256').update(normalizeSender(sender)).digest('hex');
}

/// The on-chain payload. Contains the fingerprint — never the raw
/// sender — plus risk and incident id. Well under the Memo
/// program's 566-byte limit.
export function buildMemoPayload(sender, risk, incidentId) {
  return `SWAT1|${fingerprintSender(sender)}|${risk}|${incidentId}`;
}

async function main() {
  const [sender, riskArg, incidentId] = process.argv.slice(2);
  if (!sender || !riskArg || !incidentId) {
    console.error('usage: node anchor.mjs <sender> <risk 0-100> <incidentId>');
    process.exit(2);
  }
  const payload = buildMemoPayload(sender, Number(riskArg), incidentId);
  console.log('Memo payload:', payload);

  const { Connection, Keypair, Transaction, TransactionInstruction, PublicKey, clusterApiUrl } =
    await import('@solana/web3.js');

  let payer;
  const keypairPath = process.env.SOLANA_KEYPAIR_PATH;
  if (keypairPath) {
    payer = Keypair.fromSecretKey(
      Uint8Array.from(JSON.parse(readFileSync(keypairPath, 'utf8'))),
    );
  } else {
    payer = Keypair.generate();
    console.log(
      'No SOLANA_KEYPAIR_PATH set — generated an ephemeral wallet (%s) ' +
        'with no devnet SOL, so nothing was anchored. Fund a devnet ' +
        'keypair (see README.md) and re-run to anchor for real.',
      payer.publicKey.toBase58(),
    );
    return;
  }

  const connection = new Connection(clusterApiUrl('devnet'), 'confirmed');
  const instruction = new TransactionInstruction({
    keys: [{ pubkey: payer.publicKey, isSigner: true, isWritable: false }],
    programId: new PublicKey(MEMO_PROGRAM_ID),
    data: Buffer.from(payload, 'utf8'),
  });
  const tx = new Transaction().add(instruction);
  const signature = await connection.sendTransaction(tx, [payer]);
  await connection.confirmTransaction(signature, 'confirmed');
  console.log('Anchored on Solana devnet:', signature);
  console.log('Explorer: https://explorer.solana.com/tx/%s?cluster=devnet', signature);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err.message ?? err);
    process.exit(1);
  });
}
