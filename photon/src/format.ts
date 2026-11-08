import type { ScanResult, Finding } from "../../contracts/types";

const SEV = { high: 3, medium: 2, low: 1, info: 0 } as const;
const cap = (s: string) => s[0].toUpperCase() + s.slice(1);
const oneLine = (s: string, n = 140) => { const t = s.replace(/\s+/g, " ").trim(); return t.length > n ? t.slice(0, n - 1) + "…" : t; };

export function verdictLine(r: ScanResult): string {
  const pct = Math.round(r.confidence * 100);
  if (r.confidence < 0.6 || r.verdict === "unsure") return `🤔 Not sure · only ${pct}% confident`;
  if (r.verdict === "scam") return `🚨 Likely scam · ${pct}% sure`;
  if (r.verdict === "suspicious") return `⚠️ Suspicious · ${pct}% sure`;
  return `✅ Looks safe · ${pct}% sure`;
}

export function topFindings(fs: Finding[], n = 3): Finding[] {
  return [...fs].sort((a, b) => SEV[b.severity] - SEV[a.severity] || b.confidence - a.confidence).slice(0, n);
}

export function formatReply(r: ScanResult): string {
  const lines = [verdictLine(r), ...topFindings(r.findings).map((f) => `• ${cap(f.drone)}: ${oneLine(f.explanation)}`)];
  const steps: string[] = [];
  for (const a of r.actions) {
    if (a.id === "report_7726") steps.push("Report it: forward the text to 7726 (SPAM)");
    if (a.id === "call_official") steps.push(`Call the real number${a.payload?.number ? `: ${a.payload.number}` : ""}`);
  }
  if (steps.length && r.verdict !== "safe") lines.push("", "Next steps:", ...steps.map((s) => `- ${s}`));
  lines.push("", "Reply HELP, PRIVACY or STOP.");
  return lines.join("\n");
}

export const HELP = "Signal Swarm: paste or forward a suspicious text and I will check it. Commands: HELP, PRIVACY, STOP.";
export const PRIVACY = "Privacy: your text is stripped of card numbers, SSNs, emails, addresses and codes before it is checked. Nothing is stored or kept after the reply.";
export const STOPPED = "You are unsubscribed. Text START to resume.";

export const guardianMessage = (categoryLabel: string, userAlias: string, riskScore: number) =>
  `Signal Swarm stopped a likely ${categoryLabel} scam on ${userAlias}'s phone (risk ${riskScore}). No message content was shared. Reply CALL to call them.`;
