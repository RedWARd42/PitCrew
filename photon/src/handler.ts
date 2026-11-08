import type { ScanRequest, ScanResult } from "../../contracts/types";
import { redact } from "./redact";
import { formatReply, guardianMessage, HELP, PRIVACY, STOPPED } from "./format";

export interface Guardian { userAlias: string; callNumber?: string }
export interface Deps { scan?: (req: ScanRequest) => Promise<ScanResult> }

const BACKEND = process.env.SWARM_BACKEND ?? "http://127.0.0.1:8000";
const KEY = () => process.env.SWARM_KEY ?? "dev-key";

export async function httpScan(req: ScanRequest): Promise<ScanResult> {
  const r = await fetch(`${BACKEND}/v1/scan`, {
    method: "POST", headers: { "content-type": "application/json", "X-Swarm-Key": KEY() }, body: JSON.stringify(req),
    signal: AbortSignal.timeout(8000),
  });
  if (!r.ok) throw new Error(`scan ${r.status}`);
  return r.json();
}

export function makeHandler(deps: Deps = {}) {
  const scan = deps.scan ?? httpScan;
  const stopped = new Set<string>();
  const guardians = new Map<string, Guardian>();

  return {
    guardians,
    addGuardianAlert(to: string, g: { categoryLabel: string; userAlias: string; riskScore: number; callNumber?: string }) {
      guardians.set(to, { userAlias: g.userAlias, callNumber: g.callNumber });
      return guardianMessage(g.categoryLabel, g.userAlias, g.riskScore);
    },
    async onMessage(from: string, text: string): Promise<string | null> {
      const cmd = text.trim().toUpperCase();
      if (cmd === "STOP") { stopped.add(from); return STOPPED; }
      if (cmd === "START") { stopped.delete(from); return HELP; }
      if (stopped.has(from)) return null;
      const g = guardians.get(from);
      if (g && cmd === "CALL") return g.callNumber ? `Tap to call ${g.userAlias}: tel:${g.callNumber}` : `Please call ${g.userAlias} directly.`;
      if (g && cmd === "OK") { guardians.delete(from); return "Thanks, noted."; }
      if (cmd === "HELP") return HELP;
      if (cmd === "PRIVACY") return PRIVACY;
      const { text: clean, redactions } = redact(text);
      const req: ScanRequest = {
        requestId: crypto.randomUUID(), client: "photon", mode: "incoming",
        sender: { raw: "unknown", kind: "unknown", isContact: false },
        messages: [{ id: "m1", direction: "in", text: clean }], targetMessageId: "m1", locale: "en-US", redactions,
      };
      try { return formatReply(await scan(req)); }
      catch { return "Sorry, I could not reach the scam checker. Please try again, and do not tap any links meanwhile."; }
    },
  };
}
