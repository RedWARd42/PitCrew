/**
 * Photon Voice connection settings.
 *
 * Voice on Photon is not an SDK provider — a voice application
 * (Retell, ElevenLabs, LiveKit, or Twilio) connects to the fleet's
 * Photon line over SIP, and the Photon dashboard routes calls on the
 * SMS number to it (Voice profile). This module is the single source
 * of truth for those settings; run `npm run voice:config` to print
 * what to paste into your voice provider's SIP trunk settings.
 *
 * Docs: https://photon.codes/docs/spectrum-ts/providers/voice
 */

export const VOICE_SIP = {
  /** SIP server for outbound calls from your voice application. */
  server: "sip.spectrum.photon.codes",
  /** TLS port (preferred). */
  tlsPort: 5061,
  /** TCP fallback port. */
  tcpPort: 5060,
  /** SIP username = your Spectrum project ID (env SPECTRUM_PROJECT_ID). */
  usernameEnv: "SPECTRUM_PROJECT_ID",
  /** SIP password = your Spectrum project secret (env SPECTRUM_PROJECT_SECRET). Never printed. */
  passwordEnv: "SPECTRUM_PROJECT_SECRET",
} as const;

const projectId = process.env[VOICE_SIP.usernameEnv];
const projectSecret = process.env[VOICE_SIP.passwordEnv];

console.log("Swat Fleet Line — Photon Voice (SIP) settings");
console.log("==============================================");
console.log(`SIP server : ${VOICE_SIP.server}`);
console.log(`TLS port   : ${VOICE_SIP.tlsPort} (TCP fallback ${VOICE_SIP.tcpPort})`);
console.log(
  `Username   : ${projectId ? projectId : "MISSING — set SPECTRUM_PROJECT_ID"}`,
);
console.log(
  `Password   : ${projectSecret ? "set (value never printed)" : "MISSING — set SPECTRUM_PROJECT_SECRET"}`,
);
console.log("");
console.log("Inbound calls: in the Photon dashboard, open the project's SMS");
console.log("number, add a Voice profile, and set its inbound route to your");
console.log("voice provider's SIP address (sip: for TCP, sips: for TLS).");
console.log("The agent prompt to give the voice provider lives in voice/RETELL.md.");
