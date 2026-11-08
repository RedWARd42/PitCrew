import { afterEach, describe, expect, it } from "vitest";
import {
  createFleetState,
  dispatchCandidates,
  FleetStore,
} from "../services/core/fleet";

const stores: FleetStore[] = [];
function store() {
  const state = createFleetState();
  state.useModel = false;
  const result = new FleetStore(state);
  stores.push(result);
  return result;
}
async function settled(subject: FleetStore) {
  for (let i = 0; i < 40; i++) {
    await new Promise((resolve) => setTimeout(resolve, 5));
    if (!subject.snapshot().incidents.some((i) => i.status === "investigating"))
      return subject.snapshot();
  }
  throw Error("Investigation did not settle");
}
afterEach(() => {
  for (const subject of stores.splice(0)) subject.dispose();
});

describe("sector fleet", () => {
  it("runs due upkeep only, gates readiness on lead clearance, and records shift review without transfer", async () => {
    const subject = store();
    await subject.command({ type: "scenario", scenario: "upkeep" });
    let state = await settled(subject);
    expect(state.tickets).toHaveLength(1);
    expect(state.tickets[0].maintenancePlanId).toBe("pump-inspection");
    expect(
      state.maintenancePlans.find((p) => p.id === "rack-readiness")?.status,
    ).toBe("blocked");
    expect(
      state.maintenancePlans.find((p) => p.id === "power-inspection")?.status,
    ).toBe("scheduled");
    const ticket = state.tickets[0];
    await subject.command({ type: "shift_review", technicianId: "maria" });
    expect(subject.snapshot().tickets[0].status).toBe("offered");
    expect(subject.snapshot().shiftReviews[0].openTicketIds).toEqual([
      ticket.id,
    ]);
    await expect(
      subject.command({
        type: "plan_clearance",
        planId: "rack-readiness",
        blockerId: "dependency-clearance",
        technicianId: "sam",
        note: "Synthetic dependency migration approved.",
      }),
    ).rejects.toThrow("lead");
    await subject.command({
      type: "plan_clearance",
      planId: "rack-readiness",
      blockerId: "dependency-clearance",
      technicianId: "dev",
      note: "Synthetic service owner confirms dependencies migrated and readiness inventory approved.",
    });
    state = await settled(subject);
    const readiness = state.tickets.find(
      (t) => t.maintenancePlanId === "rack-readiness",
    )!;
    expect(readiness.assigneeId).toBe("sam");
    expect(readiness.requiredSkill).toBe("hardware");
    await subject.command({
      type: "accept",
      ticketId: ticket.id,
      technicianId: "maria",
    });
    for (const step of ticket.steps)
      await subject.command({
        type: "step",
        ticketId: ticket.id,
        technicianId: "maria",
        stepId: step.id,
        note: "Inspection finding recorded.",
      });
    await subject.command({
      type: "resolve",
      ticketId: ticket.id,
      technicianId: "maria",
    });
    expect(subject.snapshot().maintenancePlans[0].status).toBe("complete");
    await subject.command({
      type: "accept",
      ticketId: readiness.id,
      technicianId: "sam",
    });
    for (let i = 0; i < 12; i++)
      await subject.command({ type: "tick", seconds: 600 });
    await expect(
      subject.command({
        type: "step",
        ticketId: readiness.id,
        technicianId: "sam",
        stepId: readiness.steps[0].id,
        note: "Late check",
      }),
    ).rejects.toThrow("outside its approved maintenance window");
  });

  it("defers overlapping upkeep to reactive field work without treating it as a completed inspection", async () => {
    const subject = store();
    await subject.command({ type: "scenario", scenario: "cooling" });
    const initial = await settled(subject);
    await subject.command({ type: "review_upkeep" });
    const state = await settled(subject);
    expect(state.tickets).toHaveLength(1);
    expect(state.maintenancePlans[0].ticketId).toBe(initial.tickets[0].id);
    expect(state.maintenancePlans[0].status).toBe("linked");
    expect(state.tickets[0].maintenancePlanId).toBeUndefined();
    await subject.command({ type: "review_upkeep" });
    expect(subject.snapshot().tickets).toHaveLength(1);
  });
  it("preserves actual work across senior handoff and requires remaining checks", async () => {
    const subject = store();
    await subject.command({ type: "scenario", scenario: "cooling" });
    const ticket = (await settled(subject)).tickets[0];
    expect(ticket.assigneeId).toBe("maria");
    await expect(
      subject.command({
        type: "accept",
        ticketId: ticket.id,
        technicianId: "jordan",
      }),
    ).rejects.toThrow("assigned technician");
    await subject.command({
      type: "accept",
      ticketId: ticket.id,
      technicianId: "maria",
    });
    await subject.command({
      type: "step",
      ticketId: ticket.id,
      technicianId: "maria",
      stepId: ticket.steps[0].id,
      note: "Independent reading confirms 5.8°F.",
    });
    await subject.command({
      type: "escalate",
      ticketId: ticket.id,
      technicianId: "maria",
      reason: "Persistent vibration needs lead review.",
    });
    const handoff = subject.snapshot().tickets[0];
    expect(handoff.assigneeId).toBe("dev");
    expect(handoff.handoff.completed.join()).toContain(
      "Independent reading confirms 5.8°F.",
    );
    expect(handoff.handoff.completed.join()).toContain("Maria Santos");
    await subject.command({
      type: "accept",
      ticketId: ticket.id,
      technicianId: "dev",
    });
    await expect(
      subject.command({
        type: "resolve",
        ticketId: ticket.id,
        technicianId: "dev",
      }),
    ).rejects.toThrow("remaining field checks");
    await subject.command({ type: "tick", seconds: 600 });
    expect(subject.snapshot().tickets[0].assigneeId).toBe("dev");
    expect(subject.snapshot().tickets).toHaveLength(1);
    for (const step of ticket.steps.slice(1))
      await subject.command({
        type: "step",
        ticketId: ticket.id,
        technicianId: "dev",
        stepId: step.id,
        note: "Observation recorded for maintenance planning.",
      });
    await subject.command({
      type: "resolve",
      ticketId: ticket.id,
      technicianId: "dev",
    });
    expect(subject.snapshot().incidents[0].status).toBe("monitoring");
    expect(subject.snapshot().sectors[0].status).not.toBe("stable");
  });

  it("escalates uncovered or expired offers but never assigns an unqualified responder", async () => {
    const subject = store();
    await subject.command({ type: "scenario", scenario: "uncovered" });
    expect((await settled(subject)).tickets[0].assigneeId).toBe("dev");
    await subject.command({ type: "scenario", scenario: "cooling" });
    await settled(subject);
    await subject.command({ type: "tick", seconds: 130 });
    expect(subject.snapshot().tickets[0].assigneeId).toBe("dev");
    await subject.command({ type: "tick", seconds: 130 });
    expect(subject.snapshot().tickets[0].assigneeId).toBeNull();
    const state = createFleetState();
    state.technicians.find((t) => t.id === "maria")!.available = false;
    state.technicians.find((t) => t.id === "dev")!.equipment = [];
    expect(
      dispatchCandidates(state, "A", "mechanical", [
        "thermal camera",
        "vibration meter",
      ]).some((c) => c.eligible),
    ).toBe(false);
  });

  it("refreshes stale simulated telemetry without a physical ticket and discards reset jobs", async () => {
    const subject = store();
    await subject.command({ type: "scenario", scenario: "sensor" });
    const state = await settled(subject);
    expect(state.tickets).toHaveLength(0);
    expect(state.sectors[2].status).toBe("stable");
    expect(state.activity.some((a) => a.tool === "refresh_telemetry")).toBe(
      true,
    );
    expect(
      state.sectors[2].memory.filter((m) => m.kind === "diagnosis"),
    ).toHaveLength(1);
    await subject.command({ type: "scenario", scenario: "cooling" });
    await subject.command({ type: "reset" });
    await settled(subject);
    expect(subject.snapshot().tickets).toHaveLength(0);
    expect(subject.snapshot().incidents).toHaveLength(0);
  });
});
