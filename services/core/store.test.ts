import { describe, it, expect, vi } from "vitest";
import { PlantStore } from "./store";
import { rankRounds } from "./engines";

describe("transactional command flows", () => {
  it("S3 owns a critical incident response within the thermal ETA and escalates owner then chief then simulated voice", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S3" });
    const incident = store.state.incidents[0]!;
    const warning = store.state.warnings[0]!;
    expect(warning).toMatchObject({
      id: `warning-${incident.id}`,
      assetId: "CDU-1",
      severity: "critical",
      ownerId: "maria",
      state: "open",
    });
    expect(
      Date.parse(warning.dueAt) - Date.parse(store.state.clock),
    ).toBeLessThanOrEqual(incident.etaMinutes! * 60000);
    expect(warning.nextAction).toContain(incident.procedureId);
    expect(warning.evidence).toContain(incident.hypothesis);
    expect(
      store.state.traces.filter((trace) => trace.agent === "Investigator"),
    ).toHaveLength(0);
    const group = store.state.messages.find(
      (message) => message.channel === "group",
    )!;
    expect(group.status).toBe("simulated");
    for (const role of ["technician", "chief", "vendor", "tenant"])
      expect(group.text).toContain(role);
    const ownerNotice = store.state.messages.find(
      (message) => message.entityId === warning.id,
    )!;
    expect(ownerNotice.personId).toBe("maria");
    await store.command({ type: "step", seconds: 44 });
    expect(
      store.state.messages.filter(
        (message) =>
          message.entityId === warning.id && message.personId === "dev",
      ),
    ).toHaveLength(0);
    await store.command({ type: "step", seconds: 1 });
    const ladder = store.state.messages.filter(
      (message) => message.entityId === warning.id,
    );
    expect(ladder.map((message) => message.personId)).toEqual([
      "maria",
      "dev",
      "dev",
    ]);
    expect(ladder[2]?.channel).toBe("voice");
    expect(ladder[2]?.text).toContain("SIMULATED CALL");
    expect(ladder[2]?.text).toContain("No phone call was placed");
    expect(store.state.warnings[0]?.state).toBe("escalated");
  });
  it("requires explicit override and logs the human reason without changing plant controls", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S2" });
    const run = store.state.runs[0]!;
    expect(run.verdict).toBe("HOLD");
    await expect(
      store.command({ type: "advance", runId: run.id }),
    ).rejects.toThrow("override");
    expect(store.state.runs[0]!.step).toBe(6);
    await store.command({
      type: "advance",
      runId: run.id,
      overrideReason: "Supervisor authorizes dry-run review only",
    });
    expect(
      store.state.audit.some((a) => a.action === "procedure.override"),
    ).toBe(true);
    expect(store.state.assets.find((a) => a.id === "PDU-4")!.status).toBe(
      "online",
    );
  });
  it("validates commands and rolls back missing entities", async () => {
    const store = new PlantStore();
    const before = structuredClone(store.state);
    await expect(
      store.command({ type: "note", assetId: "missing", text: "check pump" }),
    ).rejects.toThrow("Asset not found");
    expect(store.state).toEqual(before);
    await expect(
      store.command({ type: "reading", assetId: "CH-3", value: Infinity }),
    ).rejects.toThrow();
  });
  it("S1 creates an owned-warning opportunity and ACK records read-back", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S1" });
    expect(store.state.warnings).toHaveLength(1);
    expect(store.state.messages.length).toBeGreaterThan(0);
    const warning = store.state.warnings[0]!;
    await store.command({
      type: "ack",
      warningId: warning.id,
      readback: "I'll check pump B bearing by 02:30",
    });
    expect(store.state.warnings[0]!.state).toBe("owned");
    expect(store.state.warnings[0]!.readback).toContain("pump B");
  });
  it("S5 produces calibration work rather than a plant warning", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S5" });
    expect(store.state.warnings).toHaveLength(0);
    expect(store.state.workOrders).toHaveLength(1);
  });
  it("notifies subscribers once per committed command and supports unsubscribe", async () => {
    const store = new PlantStore();
    let calls = 0;
    const stop = store.subscribe(() => calls++);
    await store.command({ type: "step", seconds: 1 });
    expect(calls).toBe(1);
    stop();
    await store.command({ type: "step", seconds: 1 });
    expect(calls).toBe(1);
  });
  it("serializes concurrent commands without losing notes", async () => {
    const store = new PlantStore();
    const inheritedNotes = store.state.notes.length;
    await Promise.all([
      store.command({
        type: "note",
        assetId: "CH-3",
        text: "Mechanical bearing requires inspection",
      }),
      store.command({
        type: "note",
        assetId: "UPS-2",
        text: "Visual inspection completed normally",
      }),
    ]);
    expect(store.state.notes).toHaveLength(inheritedNotes + 2);
    expect(new Set(store.state.notes.map((n) => n.id)).size).toBe(
      inheritedNotes + 2,
    );
  });
  it("validates and audits advisory writes while rejecting missing references", async () => {
    const store = new PlantStore();
    await store.advisoryTool("create_work_order", {
      assetId: "CH-3",
      title: "Inspect pump B bearing",
    });
    expect(store.state.workOrders).toHaveLength(1);
    expect(store.state.audit.at(-1)?.action).toBe("tool.create_work_order");
    const before = structuredClone(store.state);
    await expect(
      store.advisoryTool("notify", {
        personId: "missing",
        text: "Please inspect",
      }),
    ).rejects.toThrow("Person not found");
    expect(store.state).toEqual(before);
    await expect(
      store.advisoryTool("stop", { assetId: "CH-3" }),
    ).rejects.toThrow();
  });
  it("starts with three concrete inherited items and preserves them when S1 begins", async () => {
    const store = new PlantStore();
    expect(store.state.handover).toHaveLength(3);
    for (const item of store.state.handover) {
      expect(
        store.state.notes.some(
          (note) =>
            item.id === `handover-${note.id}` && item.summary === note.text,
        ),
      ).toBe(true);
      expect(item.confirmed).toBe(false);
    }
    const inherited = structuredClone(store.state.handover);
    await store.command({ type: "scenario", id: "S1" });
    expect(store.state.handover).toEqual(inherited);
    expect(
      rankRounds(store.state.assets, store.state.warnings, store.state.notes)[0]
        ?.assetId,
    ).toBe("CH-3");
  });
  it("runs one simulated second per tick, pauses cleanly, and resumes from the same clock", async () => {
    vi.useFakeTimers();
    const store = new PlantStore();
    try {
      const start = Date.parse(store.state.clock);
      await store.command({ type: "pause", paused: false });
      await vi.advanceTimersByTimeAsync(3000);
      expect(Date.parse(store.state.clock) - start).toBe(3000);
      await store.command({ type: "pause", paused: true });
      await vi.advanceTimersByTimeAsync(5000);
      expect(Date.parse(store.state.clock) - start).toBe(3000);
      await store.command({ type: "pause", paused: false });
      await vi.advanceTimersByTimeAsync(2000);
      expect(Date.parse(store.state.clock) - start).toBe(5000);
      store.dispose();
      await vi.advanceTimersByTimeAsync(3000);
      expect(Date.parse(store.state.clock) - start).toBe(5000);
    } finally {
      store.dispose();
      vi.useRealTimers();
    }
  });
  it.each(["S1", "S2", "S3", "S4", "S5"] as const)(
    "%s replays an identical complete state after reset",
    async (id) => {
      const store = new PlantStore();
      store.state.cacheMode = "only";
      await store.command({ type: "scenario", id });
      const first = structuredClone(store.state);
      await store.command({ type: "step", seconds: 45 });
      await store.command({ type: "scenario", id });
      expect(store.state).toEqual(first);
    },
  );
  it("preserves receiver confirmations on unchanged regeneration and invalidates changed content", async () => {
    const store = new PlantStore();
    const item = store.state.handover[0]!;
    const readback = "I'll inspect pump B bearing on my first stop";
    await store.command({ type: "confirm", itemId: item.id, readback });
    await store.command({ type: "handover" });
    expect(
      store.state.handover.find((current) => current.id === item.id),
    ).toMatchObject({ confirmed: true, readback });
    store.state.notes.find((note) => `handover-${note.id}` === item.id)!.text +=
      " New observation: rattle is now continuous.";
    await store.command({ type: "handover" });
    expect(
      store.state.handover.find((current) => current.id === item.id),
    ).toMatchObject({ confirmed: false, readback: "" });
  });
});
