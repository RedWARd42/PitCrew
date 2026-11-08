/**
 * Calibration tests: the TS fleet must give the same scores as the
 * Flutter app's Dart engine on the app's synthetic demo inbox.
 * Run with: npm test
 */
import { analyzeMessage, pointsFor } from "./fleet.js";

let failures = 0;
function expectScore(name: string, sender: string, body: string, want: number) {
  const a = analyzeMessage(sender, body);
  const ok = a.riskScore === want;
  if (!ok) failures++;
  console.log(
    `${ok ? "PASS" : "FAIL"} ${name}: risk ${a.riskScore} (want ${want}), ` +
      `confidence ${a.confidence}, verdict ${a.verdict}`,
  );
}

const SMISH_TMOBILE =
  "T-Mobile: URGENT — your line will be SUSPENDED within 24 hours due " +
  "to an unpaid balance of $86.40. Verify NOW to keep your number " +
  "active: t-mobile-verify-secure.com/pay — scan the QR code to " +
  "confirm your account PIN and send us the 6-digit code we texted " +
  "you. Do not ignore this final notice.";

expectScore("smish-tmobile", "+1 872-555-0147", SMISH_TMOBILE, 100);
expectScore(
  "real-tmobile",
  "456",
  "T-Mobile: Your bill of $74.99 is ready. View or pay it in the " +
    "T-Mobile app, or at t-mobile.com. It is due Nov 21. Questions? " +
    "Call 611 from your T-Mobile phone.",
  0,
);
expectScore(
  "smish-chase",
  "+1 312-555-0198",
  "CHASE FRAUD ALERT: Unusual purchase of $1,240.00 at BESTBUY. If " +
    "this was not you, verify immediately at chase-secure-login.xyz — " +
    "your card will be locked if you do not respond today.",
  68,
);
expectScore(
  "smish-usps",
  "+1 640-555-0113",
  "USPS: Your package is being held at the warehouse because of an " +
    "incomplete address. Pay the $1.99 redelivery fee within 12 hours " +
    "to release it: usps-redelivery-fee.com/track",
  64,
);
expectScore(
  "mom",
  "Mom",
  "Running about 10 minutes late, traffic on 75 is awful. Start " +
    "without me if the table is ready!",
  0,
);
expectScore(
  "friend",
  "+1 214-555-0176",
  "that demo was actually insane lol. send me the link to the " +
    "arcade build when you get a chance?",
  0,
);

// The smish must trip every drone except none — all six flag it.
const smish = analyzeMessage("+1 872-555-0147", SMISH_TMOBILE);
for (const d of ["angler", "link", "scanner", "pressure", "impersonator", "swap"] as const) {
  const pts = pointsFor(smish, d);
  const ok = pts > 0;
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"} drone ${d} flagged the smish (+${pts})`);
}

if (failures) {
  console.error(`\n${failures} calibration failure(s)`);
  process.exit(1);
}
console.log("\nAll calibration tests passed.");
