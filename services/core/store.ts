import { startInvestigation, answerInvestigation } from "./investigation";
import { planDiagnostic } from "../agents/diagnostic-planner";
import {
  CommandSchema,
  StateSchema,
  type Command,
  type PlantState,
  type Warning,
} from "../../packages/contracts";
import { createInitialState, applyScenario, advanceSimulation } from "../sim";
import {
  investigate,
  guardProcedure,
  draftHandover,
  structureNote,
  coordinator,
  augmentTrace,
} from "../agents";
import {
  notifyWarning,
  processEscalations,
  acknowledge,
  sendHandover,
  enqueue,
} from "../comms";
import { parseAdvisoryMutation } from "../agents/tools";
import { persistState, loadPersistedState } from "./persistence";
import {
  authorizeVoiceTool,
  voiceIsLive,
  type VoiceTool,
} from "../comms/elevenlabs";
import { type PhotonEvent } from "../comms/photon-beta";
import { contacts, allowedPhone } from "../comms/contacts";

export class TransitionError extends Error {
  status = 409;
}
export class PlantStore {
  state: PlantState;
  private listeners = new Set<(state: PlantState) => void>();
  private queue: Promise<unknown> = Promise.resolve();
  private timer: ReturnType<typeof setInterval> | undefined;
  constructor(initial = createInitialState()) {
    this.state = StateSchema.parse(initial);
  }
  subscribe(listener: (state: PlantState) => void) {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }
  async flushCommunications() {
    if (process.env.COMMS_MODE !== "live" && !voiceIsLive()) return;
    const task = this.queue.then(async () => {
      const { flushOutbound } = await import("../comms");
      const { photonAdapter } = await import("../comms/photon");
      const { elevenLabsAdapter } = await import("../comms/elevenlabs");
      const { photonBetaAdapter } = await import("../comms/photon-beta");
      const messaging = process.env.PHOTON_PROJECT_ID?.startsWith("pho_prj_")
        ? photonBetaAdapter
        : photonAdapter;
      await flushOutbound(
        this.state,
        {
          send: (message) =>
            message.channel === "voice"
              ? elevenLabsAdapter.send(message)
              : messaging.send(message),
        },
        () => persistState(this.state),
      );
      await persistState(this.state);
      for (const listener of this.listeners)
        listener(structuredClone(this.state));
    });
    this.queue = task.catch(() => undefined);
    return task;
  }
  async command(input: Command): Promise<PlantState> {
    const command = CommandSchema.parse(input);
    const task = this.queue.then(() => this.execute(command));
    this.queue = task.catch(() => undefined);
    return task;
  }
  async voiceTool(
    input: VoiceTool,
    authorization: string | null,
  ): Promise<unknown> {
    const task = this.queue.then(async () => {
      const { warning } = authorizeVoiceTool(
        this.state,
        input.messageId,
        authorization,
      );
      if (input.kind === "context")
        return {
          clock: this.state.clock,
          warning,
          asset: this.state.assets.find((a) => a.id === warning.assetId),
          notes: this.state.notes.filter((n) => n.assetId === warning.assetId),
          incident: this.state.incidents.find((i) =>
            i.assetIds.includes(warning.assetId),
          ),
        };
      if (input.kind === "acknowledge") {
        if (warning.state === "owned") {
          if (warning.readback === input.readback)
            return { recorded: true, duplicate: true };
          throw new TransitionError("Ownership has already been recorded");
        }
        await this.execute({
          type: "ack",
          warningId: warning.id,
          readback: input.readback,
        });
      } else
        await this.execute({
          type: "note",
          assetId: warning.assetId,
          text: input.text,
        });
      return { recorded: true, warningId: warning.id };
    });
    this.queue = task.catch(() => undefined);
    return task;
  }
  async photonEvent(event: PhotonEvent) {
    const task = this.queue.then(async () => {
      if (
        this.state.audit.some(
          (a) => a.action === "photon.event" && a.detail === event.id,
        )
      )
        return;
      const object = event.data.object;
      if (
        event.type === "message.received" &&
        object.content?.type === "text"
      ) {
        const personId = Object.entries(contacts()).find(
          ([, phone]) => phone === object.sentBy?.handle,
        )?.[0];
        if (personId) {
          allowedPhone(personId);
          const match = /^own\s+(\S+)\s+(.{8,1000})$/i.exec(
            object.content.text?.trim() ?? "",
          );
          if (match) {
            const warning = this.state.warnings.find((w) => w.id === match[1]);
            if (!warning || warning.ownerId !== personId)
              throw new TransitionError(
                "Only the current owner can acknowledge",
              );
            if (warning.state !== "owned")
              await this.execute({
                type: "ack",
                warningId: warning.id,
                readback: match[2],
              });
          }
        }
      } else if (["message.delivered", "message.failed"].includes(event.type)) {
        const message = this.state.messages.find(
          (m) =>
            m.providerMessageId === object.id && m.provider === "photon-beta",
        );
        if (message && message.status !== "acked" && message.status !== "read")
          message.status = event.type === "message.failed" ? "failed" : "sent";
      }
      this.audit("photon.event", event.id);
      this.audit(event.type, `Photon resource ${object.id}`);
      await persistState(this.state);
      for (const listener of this.listeners) {
        try {
          listener(structuredClone(this.state));
        } catch {
          /* Detached subscriber. */
        }
      }
    });
    this.queue = task.catch(() => undefined);
    return task;
  }
  async advisoryTool(name: string, input: unknown): Promise<PlantState> {
    const mutation = parseAdvisoryMutation(name, input);
    const task = this.queue.then(async () => {
      const before = structuredClone(this.state);
      try {
        const warningById = (id: string) => {
          const warning = this.state.warnings.find((w) => w.id === id);
          if (!warning) throw new TransitionError("Warning not found");
          return warning;
        };
        const personById = (id: string) => {
          if (!this.state.people.some((person) => person.id === id))
            throw new TransitionError("Person not found");
        };
        switch (mutation.name) {
          case "create_warning":
            this.requireAsset(mutation.input.warning.assetId);
            personById(mutation.input.warning.ownerId);
            if (
              this.state.warnings.some(
                (w) => w.id === mutation.input.warning.id,
              )
            )
              throw new TransitionError("Warning ID already exists");
            this.state.warnings.push(mutation.input.warning);
            notifyWarning(this.state, mutation.input.warning);
            break;
          case "assign_owner":
            personById(mutation.input.personId);
            warningById(mutation.input.warningId).ownerId =
              mutation.input.personId;
            break;
          case "set_deadline":
            warningById(mutation.input.warningId).dueAt = mutation.input.dueAt;
            break;
          case "create_work_order":
            this.requireAsset(mutation.input.assetId);
            this.state.workOrders.push({
              id: `wo-${this.state.workOrders.length + 1}`,
              assetId: mutation.input.assetId,
              title: mutation.input.title,
              state: "open",
            });
            break;
          case "notify":
            personById(mutation.input.personId);
            if (mutation.input.warningId) warningById(mutation.input.warningId);
            enqueue(
              this.state,
              mutation.input.personId,
              mutation.input.warningId ?? "advisory",
              mutation.input.text,
              process.env.COMMS_MODE === "live" ? "imessage" : "terminal",
            );
            break;
          case "start_escalation":
            notifyWarning(this.state, warningById(mutation.input.warningId));
            processEscalations(this.state);
            break;
          case "open_incident_chat": {
            const incident = this.state.incidents.find(
              (i) => i.id === mutation.input.incidentId,
            );
            if (!incident) throw new TransitionError("Incident not found");
            enqueue(
              this.state,
              "dev",
              incident.id,
              `SIMULATED INCIDENT GROUP · ${incident.title}. Chief, vendor and tenant invited in the demo mirror. No group was created externally.`,
              "group",
            );
            break;
          }
          case "place_call":
            personById(mutation.input.personId);
            warningById(mutation.input.warningId);
            enqueue(
              this.state,
              mutation.input.personId,
              mutation.input.warningId,
              voiceIsLive()
                ? mutation.input.text
                : `SIMULATED CALL · ${mutation.input.text}. No phone call was placed.`,
              "voice",
            );
            break;
        }
        this.audit(
          `tool.${mutation.name}`,
          "Advisory mutation validated and recorded",
        );
        this.state = StateSchema.parse(this.state);
        await persistState(this.state);
        for (const listener of this.listeners) {
          try {
            listener(structuredClone(this.state));
          } catch {
            /* Ignore detached subscribers. */
          }
        }
        return structuredClone(this.state);
      } catch (error) {
        this.state = before;
        throw error;
      }
    });
    this.queue = task.catch(() => undefined);
    return task;
  }
  private audit(action: string, detail: string) {
    this.state.audit.push({
      id: `audit-${this.state.audit.length + 1}`,
      ts: this.state.clock,
      action,
      detail,
    });
  }
  private requireAsset(id: string) {
    const asset = this.state.assets.find((a) => a.id === id);
    if (!asset) throw new TransitionError("Asset not found");
    return asset;
  }
  private async investigateAsset(assetId: string) {
    if (
      this.state.warnings.some(
        (w) => w.assetId === assetId && w.state !== "resolved",
      )
    )
      return;
    const result = await investigate(this.state, assetId);
    if (result.trace) this.state.traces.push(result.trace);
    if (result.warning) {
      this.state.warnings.push(result.warning);
      notifyWarning(this.state, result.warning);
      this.audit("warning.created", result.warning.title);
    }
    if (
      result.workOrder &&
      !this.state.workOrders.some(
        (w) => w.assetId === assetId && w.state === "open",
      )
    ) {
      this.state.workOrders.push(result.workOrder);
      this.audit("work_order.created", result.workOrder.title);
    }
  }
  private check(procedureId: string, assetId: string, step: number) {
    this.requireAsset(assetId);
    const procedure = this.state.procedures.find((p) => p.id === procedureId);
    if (!procedure) throw new TransitionError("Procedure not found");
    if (!procedure.steps.some((s) => s.number === step))
      throw new TransitionError("Procedure step not found");
    const existing = this.state.runs.find(
      (r) =>
        r.procedureId === procedureId && r.assetId === assetId && !r.completed,
    );
    if (existing && existing.step !== step)
      throw new TransitionError(
        "Advance the current step before checking another step",
      );
    const result = guardProcedure(this.state, procedureId, assetId, step);
    const run = existing ?? {
      id: `run-${this.state.runs.length + 1}`,
      procedureId,
      assetId,
      step,
      verdict: result.verdict,
      reasoning: result.reasoning,
      completed: false,
    };
    run.verdict = result.verdict;
    run.reasoning = result.reasoning;
    if (!existing) this.state.runs.push(run);
    this.state.traces.push(result.trace);
    this.audit(
      "procedure.step_checked",
      `${procedureId} step ${step}: ${result.verdict}. ${result.reasoning}`,
    );
    return run;
  }
  private async execute(command: Command) {
    const before = structuredClone(this.state);
    try {
      switch (command.type) {
        case "reset":
          this.state = createInitialState();
          this.audit("demo.reset", "Seeded plant restored");
          break;
        case "scenario": {
          const cache = this.state.cacheMode;
          this.state = createInitialState();
          this.state.cacheMode = cache;
          applyScenario(this.state, command.id);
          this.audit("scenario.started", command.id);
          if (command.id === "S1") await this.investigateAsset("CH-3");
          if (command.id === "S2") this.check("MOP-UPS", "PDU-4", 6);
          if (command.id === "S3") {
            const result = await coordinator(this.state);
            this.state.incidents.push(result.incident);
            this.state.traces.push(result.trace);
            const incident = result.incident;
            const owner =
              this.state.people.find(
                (person) => person.role === "mechanical technician",
              ) ?? this.state.people[0]!;
            const supply = this.requireAsset("CDU-1");
            const minutesToAction = Math.max(
              0,
              Math.min(10, incident.etaMinutes ?? 5),
            );
            const warning: Warning = {
              id: `warning-${incident.id}`,
              assetId: supply.id,
              title:
                "Cooling interruption · CHW approaching 62°F restart limit",
              severity: "critical",
              ownerId: owner.id,
              dueAt: new Date(
                Date.parse(this.state.clock) + minutesToAction * 60000,
              ).toISOString(),
              state: "open",
              escalationLevel: 0,
              readback: "",
              createdAt: this.state.clock,
              evidence: [
                `${incident.alarmCount} alarms correlated into ${incident.id}`,
                incident.hypothesis,
                `CHW supply ${supply.value} ${supply.unit}; restart limit 62°F`,
                `Approximately ${incident.etaMinutes?.toFixed(0) ?? "unknown"} minutes to restart limit`,
                ...incident.assumptions,
              ],
              nextAction: `Follow ${incident.procedureId}: verify voltage stabilized and CHW supply below 62°F; coordinate an authorized operator restart with the chief. Keep vendor and tenant informed.`,
            };
            this.state.warnings.push(warning);
            notifyWarning(this.state, warning);
            this.audit(
              "warning.created",
              `${warning.id}: ${incident.id}, critical response due ${warning.dueAt}`,
            );
            enqueue(
              this.state,
              owner.id,
              incident.id,
              `INCIDENT BRIEF · ${incident.title}. ${incident.hypothesis}. CHW ${supply.value} ${supply.unit}; approximately ${incident.etaMinutes?.toFixed(0) ?? "unknown"} minutes to 62°F. Follow ${incident.procedureId}; advisory guidance requires an authorized human operator.`,
              "terminal",
            );
            const group = enqueue(
              this.state,
              "dev",
              incident.id,
              `SIMULATED INCIDENT GROUP · ${incident.id} · Hall 2 cooling. Participants: ${owner.name} (on-shift technician), Dev (chief engineer), Sam (vendor), Priya (tenant). ${incident.hypothesis}. Status: CHW ${supply.value} ${supply.unit}, approximately ${incident.etaMinutes?.toFixed(0) ?? "unknown"} minutes to 62°F. Follow ${incident.procedureId}. No external group was created.`,
              "group",
            );
            group.status = "simulated";
            this.audit("incident.opened", result.incident.title);
          }
          if (command.id === "S4") await this.investigateAsset("BAT-3");
          if (command.id === "S5") await this.investigateAsset("CRAH-1");
          break;
        }
        case "step":
          advanceSimulation(this.state, command.seconds);
          processEscalations(this.state);
          this.audit("clock.stepped", `${command.seconds} seconds`);
          break;
        case "pause":
          this.state.paused = command.paused;
          this.audit("clock.paused", String(command.paused));
          break;
        case "cache":
          this.state.cacheMode = command.mode;
          this.audit("cache.changed", command.mode);
          break;
        case "investigate": {
          const existing = this.state.investigations.find(
            (i) => i.assetId === command.assetId && i.status === "checking",
          );
          if (existing)
            throw new TransitionError(
              "An investigation is already active for this equipment.",
            );
          const record = startInvestigation(
            this.state,
            command.assetId,
            command.useModel,
          );
          this.state.investigations.push(record);
          this.audit(
            "investigation.started",
            `${record.assetId}: ${record.id}`,
          );
          break;
        }
        case "field_answer": {
          const index = this.state.investigations.findIndex(
            (i) => i.id === command.investigationId,
          );
          if (index < 0) throw new TransitionError("Investigation not found");
          this.state.investigations[index] = answerInvestigation(
            this.state.investigations[index],
            command.answer,
            command.revision,
            this.state.clock,
          );
          this.audit(
            "investigation.observed",
            `${this.state.investigations[index].assetId}: ${command.answer.checkId}`,
          );
          break;
        }
        case "take_ownership": {
          const warning = this.state.warnings.find(
            (w) => w.id === command.warningId,
          );
          if (!warning || warning.state === "resolved")
            throw new TransitionError("Active warning not found");
          if (warning.state === "owned") break;
          // Explicit button acceptance of the displayed assignment, not a fabricated human read-back.
          warning.state = "owned";
          for (const message of this.state.messages.filter(
            (m) => m.entityId === warning.id && m.direction === "outbound",
          ))
            message.status = "acked";
          this.audit(
            "warning.accepted",
            `${warning.id}: assigned action and deadline accepted`,
          );
          break;
        }
        case "reading": {
          const asset = this.requireAsset(command.assetId);
          asset.value = command.value;
          asset.history.push(command.value);
          this.audit(
            "reading.new",
            `${asset.id}: ${command.value} ${asset.unit}`,
          );
          if (
            Math.abs(command.value - asset.baseline) >
            Math.max(0.3, Math.abs(asset.baseline) * 0.08)
          )
            await this.investigateAsset(asset.id);
          break;
        }
        case "note": {
          this.requireAsset(command.assetId);
          const result = structureNote(
            this.state,
            command.assetId,
            command.text,
          );
          this.state.notes.push({
            id: `note-${this.state.notes.length + 1}`,
            assetId: command.assetId,
            author: "Maria",
            text: command.text,
            ts: this.state.clock,
            structured: result.structured,
          });
          this.state.traces.push(result.trace);
          this.audit("note.created", command.assetId);
          break;
        }
        case "complete_inspection": {
          this.requireAsset(command.assetId);
          const prefix = `${command.assetId}: `;
          // Audit order is authoritative: the simulation clock can remain paused
          // across a reading, observation, ownership read-back, and completion.
          let lastCompletion = -1;
          let lastReading = -1;
          let lastObservation = -1;
          for (const [index, entry] of this.state.audit.entries()) {
            if (
              entry.action === "inspection.completed" &&
              entry.detail.startsWith(prefix)
            )
              lastCompletion = index;
            if (
              entry.action === "reading.new" &&
              entry.detail.startsWith(prefix)
            )
              lastReading = index;
            if (
              entry.action === "note.created" &&
              entry.detail === command.assetId
            )
              lastObservation = index;
          }
          if (lastReading <= lastCompletion)
            throw new TransitionError(
              "Log a new reading before completing this inspection.",
            );
          if (lastObservation <= lastReading)
            throw new TransitionError(
              "Add an observation after the latest reading before completing this inspection.",
            );
          if (
            this.state.warnings.some(
              (warning) =>
                warning.assetId === command.assetId &&
                warning.state !== "resolved" &&
                warning.state !== "owned",
            )
          )
            throw new TransitionError(
              "Accept ownership for every open warning before completing this inspection.",
            );
          this.audit(
            "inspection.completed",
            `${prefix}reading, observation, and ownership recorded; open commitments remain active`,
          );
          break;
        }
        case "ack": {
          const warning = this.state.warnings.find(
            (w) => w.id === command.warningId,
          );
          if (!warning) throw new TransitionError("Warning not found");
          if (warning.state === "resolved")
            throw new TransitionError(
              "Resolved warning cannot be acknowledged",
            );
          acknowledge(this.state, warning, command.readback);
          this.audit("warning.acked", `${warning.id}: ${command.readback}`);
          break;
        }
        case "read": {
          const message = this.state.messages.find(
            (m) => m.id === command.messageId,
          );
          if (!message) throw new TransitionError("Message not found");
          message.status = "read";
          this.audit("message.read", message.id);
          break;
        }
        case "check":
          this.check(command.procedureId, command.assetId, command.step);
          break;
        case "advance": {
          const run = this.state.runs.find((r) => r.id === command.runId);
          if (!run || run.completed)
            throw new TransitionError("Active procedure run not found");
          const procedure = this.state.procedures.find(
            (p) => p.id === run.procedureId,
          )!;
          const current = guardProcedure(
            this.state,
            run.procedureId,
            run.assetId,
            run.step,
          );
          run.verdict = current.verdict;
          run.reasoning = current.reasoning;
          this.state.traces.push(current.trace);
          if (!procedure.approved)
            throw new TransitionError(
              "Superseded procedure cannot be overridden. Use approved revision.",
            );
          if (run.verdict === "HOLD") {
            if (
              !command.overrideReason ||
              command.overrideReason.trim().length < 12
            )
              throw new TransitionError(
                "HOLD requires an explicit override reason of at least 12 characters",
              );
            run.overrideReason = command.overrideReason.trim();
            this.audit(
              "procedure.override",
              `${run.id} step ${run.step}: ${run.overrideReason}`,
            );
          }
          this.audit(
            "procedure.step_completed",
            `${run.id} step ${run.step}; advisory record only`,
          );
          if (run.step >= procedure.steps.length) run.completed = true;
          else {
            run.step += 1;
            const next = guardProcedure(
              this.state,
              run.procedureId,
              run.assetId,
              run.step,
            );
            run.verdict = next.verdict;
            run.reasoning = next.reasoning;
            this.state.traces.push(next.trace);
          }
          break;
        }
        case "handover": {
          const result = draftHandover(this.state);
          const existing = new Map(
            this.state.handover.map((item) => [item.id, item]),
          );
          this.state.handover = result.items.map((item) => {
            const old = existing.get(item.id);
            return old &&
              old.summary === item.summary &&
              old.action === item.action
              ? { ...item, confirmed: old.confirmed, readback: old.readback }
              : item;
          });
          this.state.traces.push(result.trace);
          this.audit(
            "handover.drafted",
            `${result.items.length} walking-route items`,
          );
          break;
        }
        case "confirm": {
          const item = this.state.handover.find((i) => i.id === command.itemId);
          if (!item) throw new TransitionError("Handover item not found");
          item.confirmed = true;
          item.readback = command.readback;
          this.audit("handover.confirmed", `${item.id}: ${command.readback}`);
          if (
            this.state.handover.every((entry) => entry.confirmed) &&
            !this.state.audit.some(
              (entry) => entry.action === "handover.received",
            )
          ) {
            this.audit(
              "handover.received",
              `${this.state.handover.length} incoming items accepted with read-backs`,
            );
          }
          break;
        }
        case "send_handover":
          if (!this.state.handover.length)
            throw new TransitionError("Draft handover before sending");
          sendHandover(this.state);
          this.audit(
            "handover.sent",
            "Incoming shift briefed; unconfirmed items remain highlighted",
          );
          break;
      }
      this.state = StateSchema.parse(this.state);
      await persistState(this.state);
      this.syncClock();
      if (command.type === "investigate" || command.type === "field_answer") {
        const record =
          command.type === "investigate"
            ? this.state.investigations.at(-1)
            : this.state.investigations.find(
                (i) => i.id === command.investigationId,
              );
        if (record?.useModel)
          void this.enrichInvestigation(record.id, record.revision).catch(
            () => undefined,
          );
      }
      for (const listener of this.listeners) {
        try {
          listener(structuredClone(this.state));
        } catch {
          /* Subscriber disconnection must not roll back committed state. */
        }
      }
      if (this.state.cacheMode !== "only") {
        const oldTraces = new Set(
          command.type === "scenario" || command.type === "reset"
            ? []
            : before.traces.map((trace) => trace.id),
        );
        const pending = this.state.traces.filter(
          (trace) => !oldTraces.has(trace.id) && trace.mode === "deterministic",
        );
        if (pending.length)
          void this.enrichTraces(structuredClone(this.state), pending).catch(
            () => undefined,
          );
      }
      return structuredClone(this.state);
    } catch (error) {
      this.state = before;
      throw error;
    }
  }
  private async enrichInvestigation(id: string, revision: number) {
    const snapshot = structuredClone(this.state);
    const record = snapshot.investigations.find((i) => i.id === id);
    if (!record) return;
    const planned = await planDiagnostic(snapshot, record);
    const task = this.queue.then(async () => {
      const current = this.state.investigations.find((i) => i.id === id);
      if (!current || current.revision !== revision) return;
      const next = structuredClone(this.state);
      next.investigations[next.investigations.findIndex((i) => i.id === id)] = {
        ...planned,
        revision: revision + 1,
      };
      next.audit.push({
        id: `audit-${next.audit.length + 1}`,
        ts: next.clock,
        action: "investigation.planned",
        detail: `${record.assetId}: ${planned.mode}; next check ${planned.nextCheck ?? "review"}`,
      });
      await persistState(next);
      this.state = next;
      for (const listener of this.listeners)
        try {
          listener(structuredClone(this.state));
        } catch {}
    });
    this.queue = task.catch(() => undefined);
    await task;
  }
  private syncClock() {
    if (this.state.paused) {
      if (this.timer) clearInterval(this.timer);
      this.timer = undefined;
    } else if (!this.timer) {
      this.timer = setInterval(() => {
        void this.command({ type: "step", seconds: 1 })
          .then(() => this.flushCommunications())
          .catch(() => {
            this.state.paused = true;
            this.syncClock();
          });
      }, 1000);
      this.timer.unref?.();
    }
  }
  private async enrichTraces(
    snapshot: PlantState,
    traces: PlantState["traces"],
  ) {
    for (const trace of traces) {
      const enriched = await augmentTrace(snapshot, trace);
      const task = this.queue.then(async () => {
        const index = this.state.traces.findIndex(
          (current) =>
            current.id === trace.id &&
            current.ts === trace.ts &&
            current.trigger === trace.trigger &&
            current.summary === trace.summary,
        );
        if (index < 0) return;
        this.state.traces[index] = enriched;
        await persistState(this.state);
        for (const listener of this.listeners) {
          try {
            listener(structuredClone(this.state));
          } catch {
            /* Detached subscriber. */
          }
        }
      });
      this.queue = task.catch(() => undefined);
      await task;
    }
  }
  dispose() {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
    this.listeners.clear();
  }
}
const globalStore = globalThis as typeof globalThis & {
  groundtruthStore?: PlantStore;
  groundtruthHydration?: Promise<PlantStore>;
};
export function getStore() {
  return (globalStore.groundtruthStore ??= new PlantStore());
}
export function initializeStore() {
  return (globalStore.groundtruthHydration ??= loadPersistedState().then(
    (state) => {
      const store = getStore();
      if (state) store.state = state;
      return store;
    },
  ));
}
