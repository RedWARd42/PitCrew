import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  CommandSchema,
  StateSchema,
  type Warning,
} from "../packages/contracts";
import { PlantStore } from "../services/core/store";

beforeEach(() => {
  vi.stubEnv("DEMO_MODE", "1");
  vi.stubEnv("DEMO_CACHE", "only");
  vi.stubEnv("COMMS_MODE", "terminal");
  vi.stubEnv("VOICE_MODE", "simulated");
});
afterEach(() => vi.unstubAllEnvs());

const observation =
  "Visual observation recorded for the next shift; follow-up remains assigned.";
const complete = (store: PlantStore, assetId = "CH-3") =>
  store.command({ type: "complete_inspection", assetId });
async function recordReading(store: PlantStore, assetId = "CH-3") {
  const asset = store.state.assets.find((item) => item.id === assetId)!;
  await store.command({ type: "reading", assetId, value: asset.value });
}
async function recordObservation(store: PlantStore, assetId = "CH-3") {
  await store.command({ type: "note", assetId, text: observation });
}
async function recordInspectionInputs(store: PlantStore, assetId = "CH-3") {
  await recordReading(store, assetId);
  await recordObservation(store, assetId);
}
async function ownWarning(store: PlantStore, warningId: string) {
  await store.command({
    type: "ack",
    warningId,
    readback: "I will follow up on the bearing observation by 02:30.",
  });
}
async function expectRejectedWithoutMutation(
  store: PlantStore,
  message: RegExp,
  assetId = "CH-3",
) {
  const before = structuredClone(store.state);
  await expect(complete(store, assetId)).rejects.toThrow(message);
  expect(store.state).toEqual(before);
}

describe("inspection workflow completion", () => {
  it("adds the command without introducing a separate state field", () => {
    expect(
      CommandSchema.parse({ type: "complete_inspection", assetId: "CH-3" }),
    ).toEqual({ type: "complete_inspection", assetId: "CH-3" });
    expect(
      CommandSchema.safeParse({ type: "complete_inspection" }).success,
    ).toBe(false);
  });

  it("rejects an unknown asset and preserves state", async () => {
    const store = new PlantStore();
    await expectRejectedWithoutMutation(store, /Asset not found/, "missing");
  });

  it("requires a newly logged reading even when inherited observations exist", async () => {
    const store = new PlantStore();
    expect(store.state.notes.some((note) => note.assetId === "CH-3")).toBe(
      true,
    );
    await expectRejectedWithoutMutation(store, /new reading/);
    await recordObservation(store);
    await expectRejectedWithoutMutation(store, /new reading/);
  });

  it("requires an asset observation after the latest reading", async () => {
    const store = new PlantStore();
    await recordReading(store);
    await expectRejectedWithoutMutation(
      store,
      /observation after the latest reading/,
    );
    await recordObservation(store, "UPS-1");
    await expectRejectedWithoutMutation(
      store,
      /observation after the latest reading/,
    );
  });

  it("records an audit-only completion for equipment with no warnings", async () => {
    const store = new PlantStore();
    await recordInspectionInputs(store, "UPS-1");
    const before = structuredClone(store.state);
    const state = await complete(store, "UPS-1");
    expect(StateSchema.safeParse(state).success).toBe(true);
    expect(state.audit.at(-1)).toMatchObject({
      action: "inspection.completed",
      detail:
        "UPS-1: reading, observation, and ownership recorded; open commitments remain active",
    });
    expect(state).toEqual({
      ...before,
      audit: [...before.audit, state.audit.at(-1)],
    });
    expect(Object.keys(state).sort()).toEqual(Object.keys(before).sort());
  });

  it("requires acceptance but does not require a typed read-back", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S1" });
    await recordInspectionInputs(store);
    await expectRejectedWithoutMutation(store, /Accept ownership/);
    store.state.warnings[0]!.readback =
      "A read-back alone does not make this warning owned.";
    await expectRejectedWithoutMutation(store, /Accept ownership/);
    store.state.warnings[0]!.readback = "";
    await store.command({type:'take_ownership',warningId:store.state.warnings[0]!.id});
    await complete(store);
    expect(store.state.warnings[0]!.readback).toBe("");
  });

  it("allows an owned warning but keeps its commitments, severity, and deadline active", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S1" });
    await recordInspectionInputs(store);
    await ownWarning(store, store.state.warnings[0]!.id);
    const warnings = structuredClone(store.state.warnings);
    const workOrders = structuredClone(store.state.workOrders);
    await complete(store);
    expect(store.state.warnings).toEqual(warnings);
    expect(store.state.warnings[0]).toMatchObject({
      state: "owned",
      readback: "I will follow up on the bearing observation by 02:30.",
    });
    expect(store.state.workOrders).toEqual(workOrders);
    expect(store.state.audit.at(-1)?.detail).toContain(
      "open commitments remain active",
    );
  });

  it("rejects a new unowned warning even after an existing warning was acknowledged", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S1" });
    await recordInspectionInputs(store);
    await ownWarning(store, store.state.warnings[0]!.id);
    const additional: Warning = {
      ...structuredClone(store.state.warnings[0]!),
      id: "warning-new",
      state: "open",
      readback: "",
      title: "New follow-up requiring ownership",
    };
    store.state.warnings.push(additional);
    await expectRejectedWithoutMutation(store, /every open warning/);
    await ownWarning(store, additional.id);
    await complete(store);
    expect(store.state.warnings).toHaveLength(2);
    expect(
      store.state.warnings.every((warning) => warning.state === "owned"),
    ).toBe(true);
  });

  it("rejects duplicate completion until a new reading and subsequent observation are recorded", async () => {
    const store = new PlantStore();
    await recordInspectionInputs(store, "UPS-1");
    await complete(store, "UPS-1");
    await expectRejectedWithoutMutation(store, /new reading/, "UPS-1");
    await recordObservation(store, "UPS-1");
    await expectRejectedWithoutMutation(store, /new reading/, "UPS-1");
    await recordReading(store, "UPS-1");
    await expectRejectedWithoutMutation(
      store,
      /observation after the latest reading/,
      "UPS-1",
    );
    await recordObservation(store, "UPS-1");
    await complete(store, "UPS-1");
    expect(
      store.state.audit.filter(
        (entry) => entry.action === "inspection.completed",
      ),
    ).toHaveLength(2);
  });

  it("invalidates the old observation whenever another reading is logged for the same asset", async () => {
    const store = new PlantStore();
    await recordInspectionInputs(store, "UPS-1");
    await recordReading(store, "UPS-1");
    await expectRejectedWithoutMutation(
      store,
      /observation after the latest reading/,
      "UPS-1",
    );
    await recordObservation(store, "UPS-1");
    await complete(store, "UPS-1");
  });

  it("uses audit sequence rather than timestamps and isolates evidence by asset", async () => {
    const store = new PlantStore();
    await recordInspectionInputs(store, "UPS-1");
    await recordInspectionInputs(store, "UPS-2");
    await complete(store, "UPS-2");
    await recordReading(store, "UPS-2");
    await complete(store, "UPS-1");
    expect(new Set(store.state.audit.map((entry) => entry.ts)).size).toBe(1);
    expect(store.state.audit.at(-1)?.detail).toMatch(/^UPS-1: /);
  });

  it("does not let resolved warnings block a fresh inspection record", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S1" });
    await recordInspectionInputs(store);
    store.state.warnings[0]!.state = "resolved";
    store.state.warnings[0]!.readback = "";
    const warnings = structuredClone(store.state.warnings);
    await complete(store);
    expect(store.state.warnings).toEqual(warnings);
  });
});
