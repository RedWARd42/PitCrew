// TS mirror of contracts/models.py (PLAN.md §5.2). Used by photon/.
export type DroneId = "angler"|"link"|"pressure"|"impersonator"|"warden"|"drift"|"carrier"|"scanner";
export type ActionId = "report_7726"|"call_official"|"alert_guardian"|"block_sender"|"delete"|"mark_safe"|"dont_send"|"send_anyway";
export interface Sender { raw: string; kind: "long_code"|"short_code"|"toll_free"|"email"|"alphanumeric"|"unknown"; e164?: string; isContact: boolean }
export interface MessageIn { id: string; direction: "in"|"out"; text: string; ts?: string; hasAttachment?: boolean }
export interface EmailInfo { subject: string; fromName: string; fromAddress: string; replyTo?: string; links: { text: string; href: string }[]; attachments: { name: string }[] }
export interface ScanRequest {
  channel?: "sms"|"email"; email?: EmailInfo;
  requestId: string; client: "android"|"photon"|"web"; mode: "incoming"|"outgoing_draft";
  sender: Sender; messages: MessageIn[]; targetMessageId: string; locale: string;
  redactions: { type: string; count: number }[];
}
export interface Evidence { kind: string; value: string; source: "heuristic"|"classifier"|"reputation"|"intel"|"llm" }
export interface Anchor { messageId: string; field: "sender"|"body"|"link"|"compose"; span?: [number, number] }
export interface Finding {
  drone: DroneId; severity: "info"|"low"|"medium"|"high"; confidence: number; title: string; explanation: string;
  evidence: Evidence[]; anchor: Anchor; whatWouldChangeMyMind?: string;
}
export interface Action { id: ActionId; label: string; payload?: Record<string,string>; primary?: boolean }
export interface ScanResult {
  requestId: string; verdict: "scam"|"suspicious"|"unsure"|"safe"; riskScore: number; confidence: number;
  category?: { id: string; label: string; source: "tmobile_taxonomy"|"fallback" };
  summary: string; findings: Finding[]; actions: Action[]; riskSeries?: number[];
  privacy: { fieldsReceived: string[]; retained: false; llmUsed: boolean }; latencyMs: number; modelVersion: string;
}
