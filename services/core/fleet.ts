import { randomUUID } from "node:crypto";
import {
  FleetCommandSchema,
  type DispatchCandidate,
  type FleetActivity,
  type FleetAgentContext,
  type FleetAgentRunResult,
  type FleetCommand,
  type FleetDiagnosis,
  type FleetState,
  type FleetTicket,
  type HandoffBrief,
  type Incident,
  type MaintenancePlan,
  type Sector,
  type SectorId,
  type Skill,
  type Technician,
} from "../../packages/contracts/fleet";
import { runFleetAgents } from "../agents/fleet-agent";
import { shiftBriefSignature } from "../../packages/contracts/work-order";

const now = "2026-11-08T06:00:00.000Z";
const minutesAway: Record<SectorId, Record<SectorId, number>> = {
  A: { A: 0, B: 3, C: 5 },
  B: { A: 3, B: 0, C: 2 },
  C: { A: 5, B: 2, C: 0 },
};
const id = (prefix: string) => `${prefix}-${randomUUID()}`;
const modelName = () =>
  process.env.NEMOTRON_FLEET_MODEL ?? "nvidia/nemotron-3.5-lightning-30b-a3b";
const makeAsset = (
  id: string,
  name: string,
  metric: string,
  unit: string,
  baseline: number,
  limit: number,
) => ({
  id,
  name,
  metric,
  unit,
  baseline,
  limit,
  value: baseline,
  history: Array.from({ length: 16 }, (_, i) =>
    Number((baseline + ((i % 3) - 1) * 0.02).toFixed(2)),
  ),
  status: "normal" as const,
});

export function createFleetState(): FleetState {
  const sectors: Sector[] = [
    {
      id: "A",
      name: "Cooling plant",
      description: "Chillers, pumps and cooling distribution",
      status: "stable",
      assets: [
        makeAsset("CH-A1", "Chiller A1", "Approach temperature", "°F", 4, 8),
        makeAsset("PUMP-A2", "Pump A2", "Vibration", "mm/s", 1.8, 4.5),
      ],
      memory: [],
    },
    {
      id: "B",
      name: "Power distribution",
      description: "UPS systems and protected power paths",
      status: "stable",
      assets: [
        makeAsset("UPS-B1", "UPS B1", "Load", "%", 42, 85),
        makeAsset("PDU-B2", "PDU B2", "Cabinet temperature", "°C", 28, 45),
      ],
      memory: [],
    },
    {
      id: "C",
      name: "Compute hall",
      description: "Rack inlet conditions and environmental telemetry",
      status: "stable",
      assets: [
        makeAsset("RACK-C1", "Rack C1", "Inlet temperature", "°C", 26, 32),
        makeAsset(
          "SENSOR-C2",
          "Collector C2",
          "Reported inlet temperature",
          "°C",
          26,
          32,
        ),
      ],
      memory: [],
    },
  ];
  sectors[0].memory.push({
    id: id("memory"),
    ts: now,
    author: "Previous shift",
    kind: "observation",
    text: "Pump A2 had an intermittent rattle under load. No work has been performed; verify if the cooling trend changes.",
  });
  sectors[2].memory.push({
    id: id("memory"),
    ts: now,
    author: "Telemetry service",
    kind: "observation",
    text: "Collector C2 has a redundant rack inlet feed. Compare sample sequence and the redundant feed before requesting a physical visit.",
  });
  return {
    upkeepEnabled: false,
    shiftReviews: [],
    maintenancePlans: [
      {
        id: "pump-inspection",
        sectorId: "A",
        assetId: "PUMP-A2",
        title: "Pump A2 preventive inspection",
        kind: "inspection",
        dueAt: "2026-11-08T07:00:00.000Z",
        windowStart: now,
        windowEnd: "2026-11-08T08:00:00.000Z",
        status: "scheduled",
        requiredSkill: "mechanical",
        requiredEquipment: ["vibration meter"],
        steps: [
          "Observe pump A2 for visible leakage from a safe position.",
          "Record an independent vibration reading and compare with the maintenance baseline.",
        ],
        blockers: [],
      },
      {
        id: "rack-readiness",
        sectorId: "C",
        assetId: "RACK-C1",
        title: "Rack C1 retirement readiness check",
        kind: "retirement_readiness",
        dueAt: "2026-11-08T07:30:00.000Z",
        windowStart: now,
        windowEnd: "2026-11-08T08:00:00.000Z",
        status: "blocked",
        requiredSkill: "hardware",
        requiredEquipment: ["diagnostic tablet"],
        steps: [
          "Verify rack and device identifiers against the approved retirement inventory without disconnecting equipment.",
          "Visually document cable labels and asset tags for the retirement readiness report.",
        ],
        blockers: [
          {
            id: "dependency-clearance",
            label:
              "Service owner confirms workload dependencies migrated and inventory approved for readiness inspection",
          },
        ],
      },
      {
        id: "power-inspection",
        sectorId: "B",
        assetId: "UPS-B1",
        title: "UPS B1 external inspection",
        kind: "inspection",
        dueAt: "2026-11-08T10:30:00.000Z",
        windowStart: "2026-11-08T10:00:00.000Z",
        windowEnd: "2026-11-08T11:00:00.000Z",
        status: "scheduled",
        requiredSkill: "electrical",
        requiredEquipment: ["thermal camera"],
        steps: [
          "Observe the UPS external indicators and enclosure without opening or operating equipment.",
          "Record an external thermal image under the approved inspection procedure.",
        ],
        blockers: [],
      },
    ],
    clock: now,
    tick: 0,
    running: false,
    useModel: Boolean(process.env.NVIDIA_API_KEY),
    modelConfigured: Boolean(process.env.NVIDIA_API_KEY),
    model: modelName(),
    revision: 0,
    sectors,
    agents: sectors.flatMap((sector) =>
      (["sentinel", "investigator", "dispatcher"] as const).map((role) => ({
        id: `${sector.id}-${role}`,
        sectorId: sector.id,
        role,
        name: `${sector.id} / ${role[0].toUpperCase() + role.slice(1)}`,
        status: role === "sentinel" ? ("watching" as const) : ("idle" as const),
        mode: "deterministic" as const,
        lastAction:
          role === "sentinel"
            ? "Ready to inspect simulated telemetry"
            : "Waiting for a sector signal",
      })),
    ),
    technicians: [
      {
        id: "maria",
        name: "Maria Santos",
        title: "Mechanical technician",
        level: "technician",
        skills: ["mechanical"],
        equipment: ["thermal camera", "vibration meter"],
        clearances: ["A", "B"],
        subscriptions: ["A"],
        checkedInSector: "A",
        available: true,
        onCall: true,
      },
      {
        id: "jordan",
        name: "Jordan Lee",
        title: "Electrical technician",
        level: "technician",
        skills: ["electrical"],
        equipment: ["multimeter", "thermal camera"],
        clearances: ["A", "B"],
        subscriptions: ["B"],
        checkedInSector: "B",
        available: true,
        onCall: true,
      },
      {
        id: "sam",
        name: "Sam Patel",
        title: "Hardware & controls technician",
        level: "technician",
        skills: ["controls", "hardware"],
        equipment: ["diagnostic tablet", "thermal camera"],
        clearances: ["A", "C"],
        subscriptions: ["C"],
        checkedInSector: "C",
        available: true,
        onCall: true,
      },
      {
        id: "dev",
        name: "Dev Morgan",
        title: "On-call lead engineer",
        level: "senior",
        skills: ["mechanical", "electrical", "controls", "hardware"],
        equipment: [
          "thermal camera",
          "vibration meter",
          "multimeter",
          "diagnostic tablet",
        ],
        clearances: ["A", "B", "C"],
        subscriptions: [],
        checkedInSector: "B",
        available: true,
        onCall: true,
      },
    ],
    incidents: [],
    tickets: [],
    activity: [],
    notifications: [],
    scenario: "normal",
  };
}

/** Indoor position is a technician check-in, not GPS. Eligibility is never a model decision. */
export function dispatchCandidates(
  state: FleetState,
  sectorId: SectorId,
  skill: Skill,
  equipment: string[],
  options: { exclude?: string[]; ticketId?: string; seniorOnly?: boolean } = {},
): DispatchCandidate[] {
  const basic = state.technicians.map((technician) => {
    const reasons: string[] = [];
    if (!technician.available) reasons.push("Unavailable");
    if (!technician.onCall) reasons.push("Not on shift / on call");
    if (!technician.clearances.includes(sectorId))
      reasons.push("No sector access");
    if (!technician.skills.includes(skill))
      reasons.push(`Requires ${skill} qualification`);
    const missing = equipment.filter(
      (item) => !technician.equipment.includes(item),
    );
    if (missing.length)
      reasons.push(`Missing equipment: ${missing.join(", ")}`);
    if (options.exclude?.includes(technician.id))
      reasons.push("Already attempted or transferring this ticket");
    if (
      state.tickets.some(
        (ticket) =>
          ticket.id !== options.ticketId &&
          ticket.assigneeId === technician.id &&
          ["accepted", "in_progress"].includes(ticket.status),
      )
    )
      reasons.push("Already performing physical work");
    if (options.seniorOnly && technician.level !== "senior")
      reasons.push("Escalation requires a lead engineer");
    return { technician, reasons };
  });
  const covered =
    !options.seniorOnly &&
    basic.some(
      (item) =>
        !item.reasons.length &&
        item.technician.subscriptions.includes(sectorId),
    );
  return basic
    .map(({ technician, reasons }) => {
      const subscribed = technician.subscriptions.includes(sectorId);
      if (covered && !subscribed)
        reasons.push("Sector subscribers have first response");
      if (!covered && !(technician.level === "senior" && technician.onCall))
        reasons.push("No covered responder; on-call lead required");
      const distance = minutesAway[technician.checkedInSector][sectorId];
      const offered = state.tickets.filter(
        (t) =>
          t.id !== options.ticketId &&
          t.assigneeId === technician.id &&
          ["offered", "escalated"].includes(t.status),
      ).length;
      const eligible = !reasons.length;
      return {
        technicianId: technician.id,
        eligible,
        distance,
        score: eligible
          ? 100 - distance * 10 - offered * 20 + (subscribed ? 15 : 0)
          : -1000,
        reasons: eligible
          ? [
              subscribed
                ? `Subscribed to sector ${sectorId}`
                : "Qualified on-call lead fallback",
              `Checked in ${distance === 0 ? "in this sector" : `${distance} simulated distance units away`}`,
              `Qualified for ${skill}; required equipment and access verified`,
              ...(offered
                ? [`${offered} other pending offer${offered > 1 ? "s" : ""}`]
                : []),
            ]
          : reasons,
      };
    })
    .sort(
      (a, b) =>
        Number(b.eligible) - Number(a.eligible) ||
        b.score - a.score ||
        a.technicianId.localeCompare(b.technicianId),
    );
}

const physicalSteps = [
  "Compare the local chiller reading with an independent instrument.",
  "Observe pump A2 for unusual vibration or leakage from a safe position.",
  "Record findings and confirm the next maintenance action with the lead.",
];
function fallbackDiagnosis(
  state: FleetState,
  sectorId: SectorId,
): FleetDiagnosis {
  if (state.scenario === "sensor" && sectorId === "C")
    return {
      hypothesis:
        "A stale collector sample conflicts with the redundant inlet feed.",
      uncertainty:
        "The re-query validates the simulated collector path, not a physical sensor calibration.",
      summary:
        "Collector C2 reports an isolated spike while the redundant rack feed remains at 26°C. Re-query the synthetic collector before dispatching a technician.",
      needsHuman: false,
      requiredSkill: "controls",
      requiredEquipment: [],
      steps: [],
    };
  return {
    hypothesis:
      "Rising chiller approach temperature coincides with pump A2 vibration and the previous shift's rattle observation.",
    uncertainty:
      "A mechanical or flow issue is plausible; the cause requires independent field verification.",
    summary:
      "Cooling performance is drifting while pump vibration rises. Independent readings and an equipment observation require a qualified technician on the floor.",
    needsHuman: true,
    requiredSkill: "mechanical",
    requiredEquipment: ["thermal camera", "vibration meter"],
    steps: physicalSteps,
  };
}

export class FleetStore {
  state: FleetState;
  private queue: Promise<unknown> = Promise.resolve();
  private timer: ReturnType<typeof setInterval> | undefined;
  private epoch = 0;
  private jobs = new Map<string, number>();
  private attempted = new Map<string, Set<string>>();
  constructor(initial = createFleetState()) {
    this.state = structuredClone(initial);
  }
  snapshot() {
    return structuredClone(this.state);
  }
  command(raw: FleetCommand): Promise<FleetState> {
    const command = FleetCommandSchema.parse(raw);
    const task = this.queue.then(() => {
      const before = structuredClone(this.state);
      try {
        this.execute(command);
        this.state.revision++;
        this.syncTimer();
        return this.snapshot();
      } catch (error) {
        this.state = before;
        throw error;
      }
    });
    this.queue = task.catch(() => undefined);
    return task;
  }
  private sector(id: SectorId) {
    const sector = this.state.sectors.find((s) => s.id === id);
    if (!sector) throw Error("Unknown sector");
    return sector;
  }
  private technician(id: string) {
    const technician = this.state.technicians.find((t) => t.id === id);
    if (!technician) throw Error("Unknown technician");
    return technician;
  }
  private ticket(id: string) {
    const ticket = this.state.tickets.find((t) => t.id === id);
    if (!ticket) throw Error("Unknown ticket");
    return ticket;
  }
  private log(
    sectorId: SectorId,
    actor: string,
    actorType: FleetActivity["actorType"],
    action: string,
    detail: string,
    extra: Partial<FleetActivity> = {},
  ) {
    const item: FleetActivity = {
      id: id("activity"),
      ts: this.state.clock,
      sectorId,
      actor,
      actorType,
      action,
      detail,
      ...extra,
    };
    this.state.activity.push(item);
    if (this.state.activity.length > 600)
      this.state.activity.splice(0, this.state.activity.length - 600);
    return item.id;
  }
  private remember(
    sectorId: SectorId,
    author: string,
    kind: Sector["memory"][number]["kind"],
    text: string,
    extra: { incidentId?: string; ticketId?: string } = {},
  ) {
    const memory = {
      id: id("memory"),
      ts: this.state.clock,
      author,
      kind,
      text,
      ...extra,
    };
    this.sector(sectorId).memory.push(memory);
    return memory.id;
  }
  private agent(
    sectorId: SectorId,
    role: "sentinel" | "investigator" | "dispatcher",
    status: "watching" | "working" | "waiting" | "idle",
    lastAction: string,
    mode: "live" | "deterministic" | "fallback" = "deterministic",
  ) {
    const agent = this.state.agents.find(
      (a) => a.sectorId === sectorId && a.role === role,
    )!;
    Object.assign(agent, { status, lastAction, mode });
  }
  private handoff(ticket: FleetTicket): HandoffBrief {
    const incident = this.state.incidents.find(
      (i) => i.id === ticket.incidentId,
    )!;
    const notes = this.state.activity
      .filter((a) => a.ticketId === ticket.id && a.action === "technician.note")
      .map((a) => `${a.actor}: ${a.detail}`);
    return {
      summary: `${incident.summary}${notes.length ? ` Field notes: ${notes.slice(-3).join(" · ")}` : ""}`,
      completed: ticket.steps
        .filter((s) => s.completed)
        .map(
          (s) =>
            `${s.label}${s.note ? ` — ${s.note}` : ""} (${this.state.technicians.find((t) => t.id === s.completedBy)?.name ?? s.completedBy ?? "technician"})`,
        ),
      remaining: ticket.steps.filter((s) => !s.completed).map((s) => s.label),
      cautions: [
        incident.uncertainty,
        "Completed checks are preserved. Do not repeat them unless conditions changed.",
        "No agent operates physical equipment. Verify the current permit and plant state.",
      ],
      generatedAt: this.state.clock,
    };
  }
  private notify(ticket: FleetTicket, technicianId: string, text: string) {
    this.state.notifications.push({
      id: id("notification"),
      ts: this.state.clock,
      technicianId,
      sectorId: ticket.sectorId,
      ticketId: ticket.id,
      text,
      read: false,
    });
  }
  private dispatch(
    ticket: FleetTicket,
    reason: string,
    preferred: string | null = null,
    seniorOnly = false,
  ) {
    const attempted = this.attempted.get(ticket.id) ?? new Set<string>();
    const candidates = dispatchCandidates(
      this.state,
      ticket.sectorId,
      ticket.requiredSkill,
      ticket.requiredEquipment,
      { exclude: [...attempted], ticketId: ticket.id, seniorOnly },
    );
    // Nearby qualified responders retain priority; a model cannot route around eligibility or worsen rank.
    const best = candidates.find((c) => c.eligible);
    const suggested = candidates.find(
      (c) =>
        c.technicianId === preferred &&
        c.eligible &&
        c.score === (best?.score ?? -1),
    );
    const chosen = suggested ?? best;
    ticket.candidates = candidates;
    ticket.assigneeId = chosen?.technicianId ?? null;
    ticket.offeredAt = this.state.clock;
    ticket.deadlineAt = new Date(
      Date.parse(this.state.clock) +
        (ticket.priority === "critical" ? 60 : 120) * 1000,
    ).toISOString();
    if (chosen) {
      const tech = this.technician(chosen.technicianId);
      if (!tech.subscriptions.includes(ticket.sectorId) || seniorOnly)
        ticket.escalationLevel = Math.max(1, ticket.escalationLevel);
      ticket.status = ticket.escalationLevel ? "escalated" : "offered";
      ticket.dispatchReason = `${reason} ${tech.name}: ${chosen.reasons.join("; ")}.`;
      attempted.add(tech.id);
      this.attempted.set(ticket.id, attempted);
      this.notify(
        ticket,
        tech.id,
        `${ticket.escalationLevel ? "Escalated field work" : "New field work"}: ${ticket.title}. ${ticket.steps.filter((s) => s.completed).length} checks already completed.`,
      );
    } else {
      ticket.status = "escalated";
      ticket.escalationLevel = Math.max(1, ticket.escalationLevel);
      ticket.dispatchReason = `${reason} No eligible on-call technician has the required access, skills and equipment. Assignment remains open for the lead.`;
      for (const tech of this.state.technicians.filter(
        (t) => t.level === "senior" && t.onCall,
      ))
        this.notify(
          ticket,
          tech.id,
          `Unassigned critical coverage gap in sector ${ticket.sectorId}: arrange a qualified responder. No assignment was made.`,
        );
    }
    ticket.handoff = this.handoff(ticket);
    this.log(
      ticket.sectorId,
      `${ticket.sectorId} / Dispatcher`,
      "agent",
      "ticket.dispatched",
      ticket.dispatchReason,
      {
        ticketId: ticket.id,
        incidentId: ticket.incidentId,
        tool: "rank_eligible_technicians",
        input: {
          requiredSkill: ticket.requiredSkill,
          requiredEquipment: ticket.requiredEquipment,
          sectorId: ticket.sectorId,
        },
        output: { assigneeId: ticket.assigneeId, candidates },
        mode: "deterministic",
      },
    );
    this.remember(
      ticket.sectorId,
      "Dispatcher",
      "handoff",
      `${ticket.title}. ${ticket.dispatchReason}`,
      { ticketId: ticket.id, incidentId: ticket.incidentId },
    );
    this.agent(
      ticket.sectorId,
      "dispatcher",
      chosen ? "waiting" : "working",
      chosen
        ? `Offered ${ticket.id.slice(0, 13)} to ${this.technician(chosen.technicianId).name}`
        : "Coverage gap: no eligible technician",
    );
  }
  private assertAssignee(
    ticket: FleetTicket,
    technicianId: string,
    accepted = true,
  ) {
    const tech = this.technician(technicianId);
    if (ticket.status === "resolved")
      throw Error("This ticket is already closed");
    if (ticket.assigneeId !== tech.id)
      throw Error("Only the assigned technician can act on this ticket");
    if (accepted && !["accepted", "in_progress"].includes(ticket.status))
      throw Error("Accept the assignment before recording work");
    return tech;
  }
  private execute(command: FleetCommand) {
    switch (command.type) {
      case "review_upkeep":
        this.state.upkeepEnabled = true;
        this.evaluateUpkeep();
        break;
      case "shift_review": {
        const technician = this.technician(command.technicianId);
        const review = {
          signature: shiftBriefSignature(this.state),
          id: id("review"),
          technicianId: technician.id,
          reviewedAt: this.state.clock,
          revision: this.state.revision,
          openTicketIds: this.state.tickets
            .filter((t) => t.status !== "resolved")
            .map((t) => t.id),
          blockedPlanIds: this.state.maintenancePlans
            .filter((p) => p.status === "blocked")
            .map((p) => p.id),
        };
        this.state.shiftReviews.push(review);
        this.log(
          technician.checkedInSector,
          technician.name,
          "technician",
          "shift.reviewed",
          "Reviewed the current live shift brief. This acknowledgement does not transfer ticket ownership.",
          { output: review },
        );
        break;
      }
      case "plan_clearance": {
        const technician = this.technician(command.technicianId);
        const plan = this.state.maintenancePlans.find(
          (p) => p.id === command.planId,
        );
        if (!plan) throw Error("Unknown maintenance plan");
        if (
          technician.level !== "senior" ||
          !technician.available ||
          !technician.onCall ||
          !technician.clearances.includes(plan.sectorId)
        )
          throw Error(
            "An available on-call lead with sector access must record prerequisite clearance",
          );
        const blocker = plan.blockers.find((b) => b.id === command.blockerId);
        if (!blocker) throw Error("Unknown plan prerequisite");
        if (blocker.clearedAt)
          throw Error("This prerequisite already has recorded clearance");
        Object.assign(blocker, {
          clearedAt: this.state.clock,
          clearedBy: technician.id,
          note: command.note,
        });
        this.log(
          plan.sectorId,
          technician.name,
          "technician",
          "maintenance.clearance",
          `${blocker.label}: ${command.note}. Synthetic prerequisite evidence only; no equipment was operated or retired.`,
          { input: { planId: plan.id, blockerId: blocker.id } },
        );
        this.remember(
          plan.sectorId,
          technician.name,
          "observation",
          `Readiness prerequisite: ${command.note}. No equipment removal authorized.`,
        );
        this.state.upkeepEnabled = true;
        this.evaluateUpkeep();
        break;
      }
      case "reset":
        this.epoch++;
        this.jobs.clear();
        this.attempted.clear();
        this.state = createFleetState();
        break;
      case "scenario": {
        const useModel = this.state.useModel;
        this.epoch++;
        this.jobs.clear();
        this.attempted.clear();
        this.state = createFleetState();
        this.state.useModel = useModel;
        this.state.scenario = command.scenario;
        this.state.upkeepEnabled = command.scenario === "upkeep";
        if (
          command.scenario === "cooling" ||
          command.scenario === "uncovered"
        ) {
          const sector = this.sector("A");
          sector.assets[0].value = command.scenario === "uncovered" ? 8.3 : 5.8;
          sector.assets[0].history = [
            4,
            4.1,
            4.2,
            4.35,
            4.55,
            4.8,
            5.1,
            5.4,
            sector.assets[0].value,
          ];
          sector.assets[1].value = 3.5;
          sector.assets[1].history = [1.8, 1.9, 2.1, 2.4, 2.9, 3.5];
          if (command.scenario === "uncovered")
            for (const tech of this.state.technicians)
              tech.subscriptions = tech.subscriptions.filter((s) => s !== "A");
          this.log(
            "A",
            "Demo simulator",
            "system",
            "scenario.loaded",
            command.scenario === "uncovered"
              ? "Cooling alarm with no subscribed sector responder."
              : "Cooling drift and pump vibration injected into simulated telemetry.",
          );
        } else if (command.scenario === "sensor") {
          const sector = this.sector("C");
          sector.assets[1].value = 39;
          sector.assets[1].history = [26, 26, 26.1, 26, 39];
          this.log(
            "C",
            "Demo simulator",
            "system",
            "scenario.loaded",
            "Stale collector sample injected; redundant inlet feed stays normal.",
          );
        }
        this.inspectSignals();
        break;
      }
      case "monitor":
        this.state.running = command.running;
        this.log(
          "A",
          "Monitor",
          "system",
          "monitor.changed",
          command.running
            ? "Sector teams are monitoring simulated telemetry."
            : "Monitoring paused; active investigations can finish.",
        );
        if (command.running) this.inspectSignals();
        break;
      case "model":
        this.state.useModel = command.enabled;
        this.log(
          "A",
          "Demo operator",
          "system",
          "model.changed",
          command.enabled
            ? "New investigations may use NVIDIA Nemotron; fallback is labeled."
            : "New investigations use deterministic evidence rules.",
        );
        break;
      case "tick":
        this.advance(command.seconds);
        break;
      case "investigate":
        this.inspectSector(command.sectorId, true);
        break;
      case "technician": {
        const technician = this.technician(command.technicianId);
        if (command.sectorId) technician.checkedInSector = command.sectorId;
        if (command.available !== undefined)
          technician.available = command.available;
        if (command.subscriptions)
          technician.subscriptions = [...new Set(command.subscriptions)];
        this.log(
          technician.checkedInSector,
          technician.name,
          "technician",
          "technician.updated",
          `Checked in to sector ${technician.checkedInSector}; ${technician.available ? "available" : "unavailable"}; follows ${technician.subscriptions.join(", ") || "no sectors"}.`,
        );
        for (const ticket of this.state.tickets.filter((t) =>
          ["offered", "escalated"].includes(t.status),
        )) {
          if (ticket.assigneeId === technician.id) {
            const eligible = dispatchCandidates(
              this.state,
              ticket.sectorId,
              ticket.requiredSkill,
              ticket.requiredEquipment,
              {
                ticketId: ticket.id,
                seniorOnly:
                  ticket.escalationLevel > 0 && technician.level === "senior",
              },
            ).find((c) => c.technicianId === technician.id)?.eligible;
            if (!eligible)
              this.dispatch(
                ticket,
                "Responder eligibility changed; rerouting.",
              );
          } else if (!ticket.assigneeId) {
            this.attempted.delete(ticket.id);
            this.dispatch(
              ticket,
              "Coverage changed; checking eligible responders again.",
            );
          }
        }
        break;
      }
      case "accept": {
        const ticket = this.ticket(command.ticketId);
        this.assertWorkWindow(ticket);
        const tech = this.assertAssignee(ticket, command.technicianId, false);
        if (!["offered", "escalated"].includes(ticket.status))
          throw Error("This assignment has already been accepted");
        const candidate = dispatchCandidates(
          this.state,
          ticket.sectorId,
          ticket.requiredSkill,
          ticket.requiredEquipment,
          {
            ticketId: ticket.id,
            seniorOnly: ticket.escalationLevel > 0 && tech.level === "senior",
          },
        ).find((c) => c.technicianId === tech.id);
        if (!candidate?.eligible)
          throw Error(
            "Assignment eligibility changed. Update availability or request rerouting.",
          );
        ticket.status = "accepted";
        this.log(
          ticket.sectorId,
          tech.name,
          "technician",
          "ticket.accepted",
          "Accepted the field task and its existing evidence.",
          { ticketId: ticket.id, incidentId: ticket.incidentId },
        );
        this.remember(
          ticket.sectorId,
          tech.name,
          "action",
          "Accepted the field task.",
          { ticketId: ticket.id, incidentId: ticket.incidentId },
        );
        for (const notification of this.state.notifications.filter(
          (n) => n.ticketId === ticket.id && n.technicianId === tech.id,
        ))
          notification.read = true;
        break;
      }
      case "step": {
        const ticket = this.ticket(command.ticketId);
        this.assertWorkWindow(ticket);
        const tech = this.assertAssignee(ticket, command.technicianId);
        const step = ticket.steps.find((s) => s.id === command.stepId);
        if (!step) throw Error("Unknown field check");
        if (step.completed)
          throw Error(
            "This check is already recorded; its evidence is preserved",
          );
        Object.assign(step, {
          completed: true,
          completedAt: this.state.clock,
          completedBy: tech.id,
          note: command.note,
        });
        ticket.status = "in_progress";
        this.log(
          ticket.sectorId,
          tech.name,
          "technician",
          "technician.step",
          `${step.label}${command.note ? ` Finding: ${command.note}` : ""}`,
          { ticketId: ticket.id, incidentId: ticket.incidentId },
        );
        this.remember(
          ticket.sectorId,
          tech.name,
          "action",
          `${step.label}${command.note ? ` Finding: ${command.note}` : ""}`,
          { ticketId: ticket.id, incidentId: ticket.incidentId },
        );
        ticket.handoff = this.handoff(ticket);
        break;
      }
      case "note": {
        const ticket = this.ticket(command.ticketId);
        const tech = this.assertAssignee(ticket, command.technicianId);
        this.log(
          ticket.sectorId,
          tech.name,
          "technician",
          "technician.note",
          command.text,
          { ticketId: ticket.id, incidentId: ticket.incidentId },
        );
        this.remember(ticket.sectorId, tech.name, "observation", command.text, {
          ticketId: ticket.id,
          incidentId: ticket.incidentId,
        });
        ticket.handoff = this.handoff(ticket);
        break;
      }
      case "escalate": {
        const ticket = this.ticket(command.ticketId);
        const tech = this.assertAssignee(ticket, command.technicianId);
        ticket.escalationLevel++;
        this.log(
          ticket.sectorId,
          tech.name,
          "technician",
          "ticket.escalated",
          command.reason,
          { ticketId: ticket.id, incidentId: ticket.incidentId },
        );
        this.remember(
          ticket.sectorId,
          tech.name,
          "handoff",
          `Escalation requested: ${command.reason}`,
          { ticketId: ticket.id, incidentId: ticket.incidentId },
        );
        this.dispatch(
          ticket,
          `Escalated by ${tech.name}: ${command.reason}`,
          null,
          true,
        );
        break;
      }
      case "resolve": {
        const ticket = this.ticket(command.ticketId);
        const tech = this.assertAssignee(ticket, command.technicianId);
        if (ticket.steps.some((s) => !s.completed))
          throw Error(
            "Complete the remaining field checks before closing the work ticket",
          );
        ticket.status = "resolved";
        const incident = this.state.incidents.find(
          (i) => i.id === ticket.incidentId,
        )!;
        incident.status = "monitoring";
        const plan = this.state.maintenancePlans.find(
          (p) => p.id === ticket.maintenancePlanId,
        );
        if (plan) {
          plan.status = "complete";
          plan.lastEvaluation =
            "Approved inspection checks recorded. No equipment retirement or repair is inferred.";
        }
        ticket.handoff = this.handoff(ticket);
        ticket.handoff.cautions.unshift(
          "Field work is complete. Equipment recovery has not been inferred; telemetry monitoring continues.",
        );
        this.log(
          ticket.sectorId,
          tech.name,
          "technician",
          "ticket.closed",
          "Field work complete; telemetry monitoring continues. No equipment repair or recovery inferred.",
          { ticketId: ticket.id, incidentId: ticket.incidentId },
        );
        this.remember(
          ticket.sectorId,
          tech.name,
          "action",
          "Field work complete; monitoring continues until telemetry recovery is independently verified.",
          { ticketId: ticket.id, incidentId: ticket.incidentId },
        );
        this.agent(
          ticket.sectorId,
          "dispatcher",
          "idle",
          "Field work completed; sector remains under observation",
        );
        break;
      }
      case "read_notification": {
        const notification = this.state.notifications.find(
          (n) =>
            n.id === command.notificationId &&
            n.technicianId === command.technicianId,
        );
        if (!notification)
          throw Error("Notification not found for this technician");
        notification.read = true;
        break;
      }
    }
  }
  private advance(seconds: number) {
    this.state.clock = new Date(
      Date.parse(this.state.clock) + seconds * 1000,
    ).toISOString();
    this.state.tick++;
    if (["cooling", "uncovered"].includes(this.state.scenario)) {
      const sector = this.sector("A");
      for (const asset of sector.assets) {
        asset.value = Number(
          Math.min(
            asset.limit + 1,
            asset.value +
              ((asset.id === "CH-A1" ? 0.08 : 0.025) * seconds) / 30,
          ).toFixed(2),
        );
        asset.history = [...asset.history.slice(-23), asset.value];
      }
    }
    this.inspectSignals();
    for (const ticket of this.state.tickets.filter(
      (t) =>
        ["offered", "escalated"].includes(t.status) &&
        t.assigneeId &&
        Date.parse(t.deadlineAt) <= Date.parse(this.state.clock),
    )) {
      ticket.escalationLevel++;
      this.log(
        ticket.sectorId,
        "Dispatcher",
        "agent",
        "offer.expired",
        "No acceptance within the response window; looking for another qualified responder.",
        { ticketId: ticket.id, incidentId: ticket.incidentId },
      );
      this.dispatch(ticket, "Previous offer expired.");
    }
  }
  private inspectSignals() {
    for (const sector of this.state.sectors) this.inspectSector(sector.id);
    if (this.state.upkeepEnabled) this.evaluateUpkeep();
  }
  private assertWorkWindow(ticket: FleetTicket) {
    if (!ticket.maintenancePlanId) return;
    const current = Date.parse(this.state.clock);
    if (
      !ticket.windowStart ||
      !ticket.windowEnd ||
      current < Date.parse(ticket.windowStart) ||
      current >= Date.parse(ticket.windowEnd)
    )
      throw Error(
        "This inspection is outside its approved maintenance window. Record a note and arrange a new approved window with the lead.",
      );
  }
  private evaluateUpkeep() {
    const current = Date.parse(this.state.clock);
    for (const plan of this.state.maintenancePlans) {
      if (plan.status === "complete" || plan.status === "investigating")
        continue;
      if (current >= Date.parse(plan.windowEnd)) {
        plan.status = "blocked";
        plan.lastEvaluation =
          "Approved window has ended. Existing findings are preserved; arrange a new approved window before further inspection.";
        continue;
      }
      const linked = this.state.tickets.find((t) => t.id === plan.ticketId);
      if (linked && linked.status !== "resolved") {
        plan.status = "linked";
        plan.lastEvaluation =
          linked.maintenancePlanId === plan.id
            ? "Approved inspection already dispatched."
            : "An existing field visit covers this asset. Inspection remains deferred; closing that visit does not complete this plan.";
        continue;
      }
      if (plan.blockers.some((b) => !b.clearedAt)) {
        plan.status = "blocked";
        plan.lastEvaluation =
          "Waiting for recorded prerequisite clearance from the lead.";
        continue;
      }
      if (
        current < Date.parse(plan.windowStart) ||
        Date.parse(plan.dueAt) > current + 2 * 60 * 60 * 1000
      ) {
        plan.status = "scheduled";
        plan.lastEvaluation = "Future inspection window; no technician paged.";
        continue;
      }
      const assetName = this.sector(plan.sectorId)
        .assets.find((a) => a.id === plan.assetId)
        ?.name.toLowerCase();
      const existing = this.state.tickets.find(
        (t) =>
          t.status !== "resolved" &&
          (t.assetId === plan.assetId ||
            (t.sectorId === plan.sectorId &&
              assetName &&
              t.steps.some((s) => s.label.toLowerCase().includes(assetName)))),
      );
      if (existing) {
        plan.status = "linked";
        plan.ticketId = existing.id;
        plan.incidentId = existing.incidentId;
        plan.lastEvaluation =
          "Deferred to existing field visit; planned inspection remains incomplete.";
        this.log(
          plan.sectorId,
          "Upkeep planner",
          "agent",
          "maintenance.deferred",
          plan.lastEvaluation,
          {
            ticketId: existing.id,
            input: { planId: plan.id },
            mode: "deterministic",
          },
        );
        continue;
      }
      // Avoid concurrent jobs for one sector, preserving a coherent team memory.
      if (
        this.state.incidents.some(
          (i) => i.sectorId === plan.sectorId && i.status === "investigating",
        )
      ) {
        plan.lastEvaluation =
          "Waiting for the sector's active investigation before reviewing overlap.";
        continue;
      }
      this.launchMaintenance(plan);
    }
  }
  private launchMaintenance(plan: MaintenancePlan) {
    const fallback: FleetDiagnosis = {
      hypothesis: `Scheduled ${plan.kind === "retirement_readiness" ? "retirement readiness documentation" : "preventive inspection"} is due within its approved window.`,
      uncertainty:
        "Seeded schedule and prerequisite records do not establish equipment condition. Physical observation is required; no switching, disconnection or retirement is authorized.",
      summary: `${plan.title}. Approved window ${plan.windowStart} to ${plan.windowEnd}. Record the bounded inspection findings; this task does not perform repairs or retire equipment.`,
      needsHuman: true,
      requiredSkill: plan.requiredSkill,
      requiredEquipment: plan.requiredEquipment,
      steps: plan.steps,
    };
    const incident: Incident = {
      id: id("incident"),
      sectorId: plan.sectorId,
      assetId: plan.assetId,
      title: plan.title,
      summary: fallback.summary,
      severity: "watch",
      status: "investigating",
      hypothesis: fallback.hypothesis,
      uncertainty: fallback.uncertainty,
      requiredSkill: plan.requiredSkill,
      requiredEquipment: [...plan.requiredEquipment],
      evidenceIds: [],
      mode: "deterministic",
      createdAt: this.state.clock,
      kind: "maintenance",
      maintenancePlanId: plan.id,
      dueAt: plan.dueAt,
      windowStart: plan.windowStart,
      windowEnd: plan.windowEnd,
    };
    this.state.incidents.push(incident);
    plan.status = "investigating";
    plan.incidentId = incident.id;
    plan.ticketId = undefined;
    plan.lastEvaluation =
      "Sector agents are reviewing the schedule, prerequisites and physical inspection scope.";
    incident.evidenceIds.push(
      this.remember(
        plan.sectorId,
        "Upkeep planner",
        "observation",
        fallback.summary,
        { incidentId: incident.id },
      ),
    );
    this.log(
      plan.sectorId,
      "Upkeep planner",
      "agent",
      "maintenance.review",
      plan.lastEvaluation,
      {
        incidentId: incident.id,
        tool: "evaluate_maintenance_window",
        input: { planId: plan.id },
        output: { withinWindow: true, prerequisitesCleared: true },
        mode: "deterministic",
      },
    );
    this.agent(
      plan.sectorId,
      "investigator",
      "working",
      "Reviewing maintenance evidence and approved physical checks",
    );
    const context: FleetAgentContext = {
      state: this.snapshot(),
      sectorId: plan.sectorId,
      incidentId: incident.id,
      candidates: dispatchCandidates(
        this.state,
        plan.sectorId,
        plan.requiredSkill,
        plan.requiredEquipment,
      ),
      fallback,
    };
    this.jobs.set(incident.id, this.epoch);
    void this.run(context, this.epoch);
  }
  private inspectSector(sectorId: SectorId, force = false) {
    const sector = this.sector(sectorId);
    for (const asset of sector.assets)
      asset.status =
        asset.value >= asset.limit
          ? "alarm"
          : asset.value >=
              asset.baseline + (asset.limit - asset.baseline) * 0.35
            ? "drifting"
            : "normal";
    sector.status = sector.assets.some((a) => a.status === "alarm")
      ? "critical"
      : sector.assets.some((a) => a.status === "drifting")
        ? "watch"
        : "stable";
    this.agent(
      sectorId,
      "sentinel",
      "watching",
      sector.status === "stable"
        ? "Telemetry within seeded operating range"
        : `Detected ${sector.status === "critical" ? "an alarm" : "a developing trend"}; checking shared context`,
    );
    const existing = this.state.incidents.find(
      (i) =>
        i.sectorId === sectorId &&
        i.status !== "resolved" &&
        i.kind !== "maintenance",
    );
    if (existing) {
      if (sector.status === "critical" && existing.severity !== "critical") {
        existing.severity = "critical";
        for (const ticket of this.state.tickets.filter(
          (item) =>
            item.incidentId === existing.id && item.status !== "resolved",
        )) {
          ticket.priority = "critical";
          if (["offered", "escalated"].includes(ticket.status)) {
            ticket.deadlineAt = new Date(
              Math.min(
                Date.parse(ticket.deadlineAt),
                Date.parse(ticket.offeredAt) + 60_000,
              ),
            ).toISOString();
          }
          if (ticket.assigneeId)
            this.notify(
              ticket,
              ticket.assigneeId,
              "Sector conditions crossed the simulated alarm limit. Review the updated critical priority.",
            );
        }
        this.log(
          sectorId,
          `${sectorId} / Sentinel`,
          "agent",
          "incident.promoted",
          "A developing issue crossed the simulated alarm limit; active work priority and unaccepted response windows were raised.",
          { incidentId: existing.id, mode: "deterministic" },
        );
      }
      return;
    }
    if (!force && sector.status === "stable") return;
    if (sector.status === "stable") {
      this.log(
        sectorId,
        `${sectorId} / Sentinel`,
        "agent",
        "monitor.checked",
        "No actionable signal in this sector; no ticket created.",
        {
          tool: "read_sector_vitals",
          output: sector.assets,
          mode: "deterministic",
        },
      );
      return;
    }
    const asset = sector.assets.find((a) => a.status !== "normal")!;
    const fallback = fallbackDiagnosis(this.state, sectorId);
    const evidenceId = this.remember(
      sectorId,
      `${sectorId} / Sentinel`,
      "observation",
      `${asset.name}: ${asset.value} ${asset.unit}; baseline ${asset.baseline}, limit ${asset.limit}.`,
    );
    const incident: Incident = {
      id: id("incident"),
      sectorId,
      assetId: asset.id,
      title:
        sectorId === "C"
          ? "Collector sample disagrees with redundant feed"
          : "Cooling drift requires field verification",
      summary: fallback.summary,
      severity: sector.status === "critical" ? "critical" : "watch",
      status: "investigating",
      hypothesis: fallback.hypothesis,
      uncertainty: fallback.uncertainty,
      requiredSkill: fallback.requiredSkill,
      requiredEquipment: fallback.requiredEquipment,
      evidenceIds: [evidenceId],
      mode: "deterministic",
      createdAt: this.state.clock,
    };
    this.state.incidents.push(incident);
    this.log(
      sectorId,
      `${sectorId} / Sentinel`,
      "agent",
      "incident.detected",
      incident.title,
      {
        incidentId: incident.id,
        tool: "read_sector_vitals",
        output: sector.assets,
        mode: "deterministic",
      },
    );
    this.agent(
      sectorId,
      "investigator",
      "working",
      "Comparing telemetry, peer evidence and shared memory",
    );
    this.agent(
      sectorId,
      "dispatcher",
      "waiting",
      "Waiting for diagnosis before creating human work",
    );
    const context: FleetAgentContext = {
      state: this.snapshot(),
      sectorId,
      incidentId: incident.id,
      candidates: dispatchCandidates(
        this.state,
        sectorId,
        fallback.requiredSkill,
        fallback.requiredEquipment,
      ),
      fallback,
    };
    const epoch = this.epoch;
    this.jobs.set(incident.id, epoch);
    void this.run(context, epoch);
  }
  private async run(context: FleetAgentContext, epoch: number) {
    let result: FleetAgentRunResult;
    try {
      result = await runFleetAgents(context);
    } catch {
      result = {
        mode: "fallback",
        model: modelName(),
        diagnosis: context.fallback,
        selectedTechnicianId: null,
        calls: [],
      };
    }
    const task = this.queue.then(() => {
      if (epoch !== this.epoch || this.jobs.get(context.incidentId) !== epoch)
        return;
      const incident = this.state.incidents.find(
        (i) => i.id === context.incidentId,
      );
      if (!incident || incident.status !== "investigating") return;
      const fallback = context.fallback;
      const plan = this.state.maintenancePlans.find(
        (p) => p.id === incident.maintenancePlanId,
      );
      if (
        plan &&
        (Date.parse(this.state.clock) >= Date.parse(plan.windowEnd) ||
          plan.blockers.some((b) => !b.clearedAt))
      ) {
        plan.status = "blocked";
        plan.lastEvaluation =
          "Window or prerequisites changed during review; no field ticket issued.";
        incident.status = "monitoring";
        this.jobs.delete(incident.id);
        this.agent(
          context.sectorId,
          "investigator",
          "idle",
          plan.lastEvaluation,
        );
        this.agent(
          context.sectorId,
          "dispatcher",
          "idle",
          "Maintenance dispatch blocked",
        );
        this.log(
          plan.sectorId,
          "Upkeep planner",
          "agent",
          "maintenance.blocked",
          plan.lastEvaluation,
          { incidentId: incident.id },
        );
        this.state.revision++;
        return;
      }
      const diagnosis = result.diagnosis;
      incident.mode = result.mode;
      incident.summary = diagnosis.summary?.slice(0, 2000) || fallback.summary;
      incident.hypothesis =
        diagnosis.hypothesis?.slice(0, 1500) || fallback.hypothesis;
      incident.uncertainty =
        diagnosis.uncertainty?.slice(0, 1500) || fallback.uncertainty;
      // Model wording cannot weaken physical-work prerequisites or invent an equipment procedure.
      incident.requiredSkill = fallback.requiredSkill;
      const knownEquipment = new Set(
        this.state.technicians.flatMap((t) => t.equipment),
      );
      incident.requiredEquipment = [
        ...new Set([
          ...fallback.requiredEquipment,
          ...(diagnosis.requiredEquipment ?? []).filter((item) =>
            knownEquipment.has(item),
          ),
        ]),
      ];
      for (const call of result.calls)
        this.log(
          context.sectorId,
          `${context.sectorId} / ${call.agent === "investigator" ? "Investigator" : "Dispatcher"}`,
          "agent",
          "agent.tool",
          call.summary,
          {
            incidentId: incident.id,
            tool: call.tool,
            input: call.input,
            output: call.output,
            mode: result.mode,
          },
        );
      const memoryCall = [...result.calls]
        .reverse()
        .find(
          (call) =>
            call.tool === "write_shared_memory" &&
            call.output &&
            typeof call.output === "object" &&
            "text" in call.output &&
            typeof call.output.text === "string",
        );
      const memoryText = memoryCall
        ? (memoryCall.output as { text: string }).text.slice(0, 4000)
        : `${incident.hypothesis} ${incident.uncertainty}`;
      const memory = this.remember(
        context.sectorId,
        `${context.sectorId} / Investigator`,
        "diagnosis",
        memoryText,
        { incidentId: incident.id },
      );
      incident.evidenceIds.push(memory);
      this.agent(
        context.sectorId,
        "investigator",
        "idle",
        incident.hypothesis,
        result.mode,
      );
      if (!fallback.needsHuman) {
        incident.status = "monitoring";
        const sector = this.sector(context.sectorId);
        const collector = sector.assets.find((a) => a.id === "SENSOR-C2");
        const redundant = sector.assets.find((a) => a.id === "RACK-C1");
        if (collector && redundant) {
          collector.value = redundant.value;
          collector.history = [
            ...collector.history.slice(-23),
            collector.value,
          ];
          collector.status = "normal";
          sector.status = "stable";
        }
        this.log(
          context.sectorId,
          `${context.sectorId} / Investigator`,
          "agent",
          "telemetry.refreshed",
          "Replayed the latest redundant simulated sample into the stale collector view. No physical equipment was changed and no technician ticket was created.",
          {
            incidentId: incident.id,
            tool: "refresh_telemetry",
            input: { collector: "SENSOR-C2", source: "RACK-C1" },
            output: {
              sample: collector?.value,
              physicalEquipmentChanged: false,
            },
            mode: "deterministic",
          },
        );
        this.remember(
          context.sectorId,
          "Investigator",
          "action",
          "Synthetic collector re-query agrees with the redundant inlet feed; continue monitoring. No physical task needed.",
          { incidentId: incident.id },
        );
        this.agent(
          context.sectorId,
          "dispatcher",
          "idle",
          "No human work needed; technician capacity preserved",
          result.mode,
        );
        this.agent(
          context.sectorId,
          "sentinel",
          "watching",
          "Collector refreshed; redundant feed agrees",
        );
      } else {
        incident.status = "needs_human";
        const proposed = (diagnosis.steps ?? []).filter((step) =>
          fallback.steps.includes(step),
        );
        const steps = [...new Set([...proposed, ...fallback.steps])];
        const ticket: FleetTicket = {
          kind: incident.kind ?? "reactive",
          maintenancePlanId: incident.maintenancePlanId,
          dueAt: incident.dueAt,
          windowStart: incident.windowStart,
          windowEnd: incident.windowEnd,
          id: id("ticket"),
          incidentId: incident.id,
          sectorId: context.sectorId,
          assetId: incident.assetId,
          title: incident.title,
          summary: incident.summary,
          priority: incident.severity,
          status: "offered",
          assigneeId: null,
          requiredSkill: incident.requiredSkill,
          requiredEquipment: incident.requiredEquipment,
          createdAt: this.state.clock,
          offeredAt: this.state.clock,
          deadlineAt: this.state.clock,
          escalationLevel: 0,
          dispatchReason: "",
          candidates: [],
          steps: steps.map((label, index) => ({
            id: `check-${index + 1}`,
            label,
            completed: false,
          })),
          handoff: {
            summary: "",
            completed: [],
            remaining: [],
            cautions: [],
            generatedAt: this.state.clock,
          },
        };
        this.state.tickets.push(ticket);
        if (plan) {
          plan.ticketId = ticket.id;
          plan.status = "linked";
          plan.lastEvaluation =
            "Approved physical inspection dispatched with its schedule and prerequisite evidence.";
        }
        this.log(
          context.sectorId,
          `${context.sectorId} / Dispatcher`,
          "agent",
          "ticket.created",
          "Created physical-only field work with evidence and approved observation checks.",
          {
            ticketId: ticket.id,
            incidentId: incident.id,
            tool: "create_field_ticket",
            input: {
              requiredSkill: ticket.requiredSkill,
              requiredEquipment: ticket.requiredEquipment,
            },
            output: { ticketId: ticket.id, steps: ticket.steps },
            mode: result.mode,
          },
        );
        this.dispatch(
          ticket,
          "Nearest qualified covered responder selected.",
          result.selectedTechnicianId,
        );
        this.agent(
          context.sectorId,
          "dispatcher",
          "waiting",
          ticket.assigneeId
            ? `Awaiting ${this.technician(ticket.assigneeId).name}'s acceptance`
            : "No eligible responder; lead coverage requested",
          result.mode,
        );
      }
      this.jobs.delete(incident.id);
      this.state.revision++;
    });
    this.queue = task.catch(() => undefined);
    await task;
  }
  private syncTimer() {
    if (!this.state.running) {
      if (this.timer) clearInterval(this.timer);
      this.timer = undefined;
    } else if (!this.timer) {
      this.timer = setInterval(
        () =>
          void this.command({ type: "tick", seconds: 30 }).catch(() => {
            this.state.running = false;
            this.syncTimer();
          }),
        5000,
      );
      this.timer.unref?.();
    }
  }
  dispose() {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
    this.epoch++;
    this.jobs.clear();
  }
}

const globalFleet = globalThis as typeof globalThis & {
  groundtruthFleet?: FleetStore;
};
export function getFleetStore() {
  return (globalFleet.groundtruthFleet ??= new FleetStore());
}
