import { z } from "zod";
export type SectorId = "A" | "B" | "C";
export type AgentMode = "live" | "deterministic" | "fallback";
export type Skill = "mechanical" | "electrical" | "controls" | "hardware";
export interface FleetAsset {
  id: string;
  name: string;
  metric: string;
  unit: string;
  value: number;
  baseline: number;
  limit: number;
  history: number[];
  status: "normal" | "drifting" | "alarm";
}
export interface SharedMemory {
  id: string;
  ts: string;
  author: string;
  kind: "observation" | "diagnosis" | "action" | "handoff";
  text: string;
  incidentId?: string;
  ticketId?: string;
}
export interface Sector {
  id: SectorId;
  name: string;
  description: string;
  status: "stable" | "watch" | "critical";
  assets: FleetAsset[];
  memory: SharedMemory[];
}
export interface FleetAgent {
  id: string;
  sectorId: SectorId;
  role: "sentinel" | "investigator" | "dispatcher";
  name: string;
  status: "watching" | "working" | "waiting" | "idle";
  mode: AgentMode;
  lastAction: string;
}
export interface Technician {
  id: string;
  name: string;
  title: string;
  level: "technician" | "senior";
  skills: Skill[];
  equipment: string[];
  clearances: SectorId[];
  subscriptions: SectorId[];
  checkedInSector: SectorId;
  available: boolean;
  onCall: boolean;
}
export interface DispatchCandidate {
  technicianId: string;
  eligible: boolean;
  distance: number;
  score: number;
  reasons: string[];
}
export interface Incident {
  maintenancePlanId?: string;
  kind?: "reactive" | "maintenance";
  dueAt?: string;
  windowStart?: string;
  windowEnd?: string;
  id: string;
  sectorId: SectorId;
  assetId: string;
  title: string;
  summary: string;
  severity: "watch" | "critical";
  status: "investigating" | "needs_human" | "monitoring" | "resolved";
  hypothesis: string;
  uncertainty: string;
  requiredSkill: Skill;
  requiredEquipment: string[];
  evidenceIds: string[];
  mode: AgentMode;
  createdAt: string;
}
export interface TicketStep {
  id: string;
  label: string;
  completed: boolean;
  completedAt?: string;
  completedBy?: string;
  note?: string;
}
export interface HandoffBrief {
  summary: string;
  completed: string[];
  remaining: string[];
  cautions: string[];
  generatedAt: string;
}
export interface FleetTicket {
  maintenancePlanId?: string;
  kind?: "reactive" | "maintenance";
  dueAt?: string;
  windowStart?: string;
  windowEnd?: string;
  id: string;
  incidentId: string;
  sectorId: SectorId;
  assetId: string;
  title: string;
  summary: string;
  priority: "watch" | "critical";
  status: "offered" | "accepted" | "in_progress" | "escalated" | "resolved";
  assigneeId: string | null;
  requiredSkill: Skill;
  requiredEquipment: string[];
  createdAt: string;
  offeredAt: string;
  deadlineAt: string;
  escalationLevel: number;
  dispatchReason: string;
  candidates: DispatchCandidate[];
  steps: TicketStep[];
  handoff: HandoffBrief;
}
export interface FleetActivity {
  id: string;
  ts: string;
  sectorId: SectorId;
  actor: string;
  actorType: "agent" | "technician" | "system";
  action: string;
  detail: string;
  tool?: string;
  input?: unknown;
  output?: unknown;
  mode?: AgentMode;
  incidentId?: string;
  ticketId?: string;
}
export interface FleetNotification {
  id: string;
  ts: string;
  technicianId: string;
  sectorId: SectorId;
  ticketId: string;
  text: string;
  read: boolean;
}
export interface MaintenancePlan {
  id: string;
  sectorId: SectorId;
  assetId: string;
  title: string;
  kind: "inspection" | "retirement_readiness";
  dueAt: string;
  windowStart: string;
  windowEnd: string;
  status: "scheduled" | "blocked" | "investigating" | "linked" | "complete";
  requiredSkill: Skill;
  requiredEquipment: string[];
  steps: string[];
  blockers: Array<{
    id: string;
    label: string;
    clearedAt?: string;
    clearedBy?: string;
    note?: string;
  }>;
  ticketId?: string;
  incidentId?: string;
  lastEvaluation?: string;
}
export interface ShiftReview {
  signature: string;
  id: string;
  technicianId: string;
  reviewedAt: string;
  revision: number;
  openTicketIds: string[];
  blockedPlanIds: string[];
}
export interface FleetState {
  upkeepEnabled: boolean;
  maintenancePlans: MaintenancePlan[];
  shiftReviews: ShiftReview[];
  clock: string;
  tick: number;
  running: boolean;
  useModel: boolean;
  modelConfigured: boolean;
  model: string;
  revision: number;
  sectors: Sector[];
  agents: FleetAgent[];
  technicians: Technician[];
  incidents: Incident[];
  tickets: FleetTicket[];
  activity: FleetActivity[];
  notifications: FleetNotification[];
  scenario: "normal" | "cooling" | "sensor" | "uncovered" | "upkeep";
}
export const FleetCommandSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("review_upkeep") }),
  z.object({
    type: z.literal("plan_clearance"),
    planId: z.string(),
    blockerId: z.string(),
    technicianId: z.string(),
    note: z.string().trim().min(10).max(1500),
  }),
  z.object({ type: z.literal("shift_review"), technicianId: z.string() }),
  z.object({ type: z.literal("reset") }),
  z.object({
    type: z.literal("scenario"),
    scenario: z.enum(["normal", "cooling", "sensor", "uncovered", "upkeep"]),
  }),
  z.object({ type: z.literal("monitor"), running: z.boolean() }),
  z.object({
    type: z.literal("tick"),
    seconds: z.number().int().min(1).max(600).default(30),
  }),
  z.object({ type: z.literal("model"), enabled: z.boolean() }),
  z.object({
    type: z.literal("investigate"),
    sectorId: z.enum(["A", "B", "C"]),
  }),
  z.object({
    type: z.literal("technician"),
    technicianId: z.string(),
    sectorId: z.enum(["A", "B", "C"]).optional(),
    available: z.boolean().optional(),
    subscriptions: z.array(z.enum(["A", "B", "C"])).optional(),
  }),
  z.object({
    type: z.literal("accept"),
    ticketId: z.string(),
    technicianId: z.string(),
  }),
  z.object({
    type: z.literal("step"),
    ticketId: z.string(),
    stepId: z.string(),
    technicianId: z.string(),
    note: z.string().trim().max(1500).default(""),
  }),
  z.object({
    type: z.literal("note"),
    ticketId: z.string(),
    technicianId: z.string(),
    text: z.string().trim().min(1).max(1500),
  }),
  z.object({
    type: z.literal("escalate"),
    ticketId: z.string(),
    technicianId: z.string(),
    reason: z.string().trim().min(3).max(1000),
  }),
  z.object({
    type: z.literal("resolve"),
    ticketId: z.string(),
    technicianId: z.string(),
  }),
  z.object({
    type: z.literal("read_notification"),
    notificationId: z.string(),
    technicianId: z.string(),
  }),
]);
export type FleetCommand = z.infer<typeof FleetCommandSchema>;

/** Model-facing bounded result. Backend revalidates physical work and dispatch eligibility. */
export interface FleetDiagnosis {
  hypothesis: string;
  uncertainty: string;
  summary: string;
  needsHuman: boolean;
  requiredSkill: Skill;
  requiredEquipment: string[];
  steps: string[];
}
export interface FleetAgentRunResult {
  mode: AgentMode;
  model: string;
  diagnosis: FleetDiagnosis;
  selectedTechnicianId: string | null;
  calls: Array<{
    agent: "investigator" | "dispatcher";
    tool: string;
    input: unknown;
    output: unknown;
    summary: string;
  }>;
}
export interface FleetAgentContext {
  state: FleetState;
  sectorId: SectorId;
  incidentId: string;
  candidates: DispatchCandidate[];
  fallback: FleetDiagnosis;
}
