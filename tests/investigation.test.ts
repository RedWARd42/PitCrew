import { describe, it, expect } from "vitest";
import { PlantStore } from "../services/core/store";
import { CommandSchema } from "../packages/contracts";
import { draftHandover } from "../services/agents";
import { planDiagnostic } from "../services/agents/diagnostic-planner";
async function start(scenario: "S1" | "S5" = "S1") {
  const store = new PlantStore();
  await store.command({ type: "scenario", id: scenario });
  await store.command({
    type: "investigate",
    assetId: scenario === "S1" ? "CH-3" : "CRAH-1",
    useModel: false,
  });
  return store;
}
async function answer(
  store: PlantStore,
  answer: Extract<
    import("../packages/contracts").Command,
    { type: "field_answer" }
  >["answer"],
) {
  const record = store.state.investigations[0];
  await store.command({
    type: "field_answer",
    investigationId: record.id,
    revision: record.revision,
    answer,
  });
  return store.state.investigations[0];
}
describe("adaptive field investigation", () => {
  it("separates independent evidence from telemetry and changes the working assessment", async () => {
    const store = await start();
    const telemetry = structuredClone(store.state.assets);
    let record = await answer(store, { checkId: "local_reading", value: 5.5 });
    expect(record.nextCheck).toBe("physical_check");
    record = await answer(store, {
      checkId: "physical_check",
      condition: "abnormal",
    });
    expect(record.status).toBe("review");
    expect(record.hypotheses[1].status).toBe("supported");
    expect(store.state.assets).toEqual(telemetry);
    expect(store.state.warnings[0].state).not.toBe("resolved");
  });
  it("routes a sensor disagreement through a repeat measurement", async () => {
    const store = await start("S5");
    let record = await answer(store, { checkId: "local_reading", value: 74 });
    expect(record.nextCheck).toBe("repeat_reading");
    record = await answer(store, { checkId: "repeat_reading", value: 74.1 });
    expect(record.nextCheck).toBe("physical_check");
    record = await answer(store, {
      checkId: "physical_check",
      condition: "normal",
    });
    expect(record.status).toBe("review");
    expect(record.summary).toContain("measurement issue");
    expect(record.hypotheses[0].status).toBe("supported");
  });
  it("does not turn an uncertain observation into a diagnosis", async () => {
    const store = await start();
    await answer(store, { checkId: "local_reading", value: 5.5 });
    const record = await answer(store, {
      checkId: "physical_check",
      condition: "uncertain",
    });
    expect(record.hypotheses[1].status).toBe("unresolved");
    expect(record.nextCheck).toBe("repeat_reading");
  });
  it("rejects duplicate, stale, and out-of-order evidence atomically", async () => {
    const store = await start();
    const record = store.state.investigations[0];
    const before = structuredClone(store.state);
    await expect(
      store.command({
        type: "field_answer",
        investigationId: record.id,
        revision: record.revision,
        answer: { checkId: "physical_check", condition: "normal" },
      }),
    ).rejects.toThrow("current field check");
    expect(store.state).toEqual(before);
    await answer(store, { checkId: "local_reading", value: 5.5 });
    await expect(
      store.command({
        type: "field_answer",
        investigationId: record.id,
        revision: record.revision,
        answer: { checkId: "local_reading", value: 5.5 },
      }),
    ).rejects.toThrow("changed");
  });
  it("rejects malformed answers and unsupported assets", async () => {
    expect(
      CommandSchema.safeParse({
        type: "field_answer",
        investigationId: "x",
        revision: 0,
        answer: { checkId: "local_reading", condition: "normal" },
      }).success,
    ).toBe(false);
    const store = await start();
    await expect(
      store.command({ type: "investigate", assetId: "UPS-1", useModel: false }),
    ).rejects.toThrow("Choose cooling");
  });
  it("carries partial evidence and unfinished checks into handover", async () => {
    const store = await start();
    await answer(store, { checkId: "local_reading", value: 5.5 });
    const item = draftHandover(store.state).items.find((i) =>
      i.id.startsWith("handover-investigation-"),
    )!;
    expect(item.summary).toContain("5.5");
    expect(item.action).toContain("physical check");
  });
  it("accepts ownership without fabricating a human read-back", async () => {
    const store = await start();
    const id = store.state.warnings[0].id;
    await store.command({ type: "take_ownership", warningId: id });
    expect(store.state.warnings[0].state).toBe("owned");
    expect(store.state.warnings[0].readback).toBe("");
    expect(store.state.audit.at(-1)?.action).toBe("warning.accepted");
  });
  it("honestly labels deterministic mode without calling a model", async () => {
    const store = await start();
    const result = await planDiagnostic(
      store.state,
      store.state.investigations[0],
    );
    expect(result.mode).toBe("deterministic");
    expect(result.calls).toHaveLength(0);
  });
  it('keeps contradictory repeat measurements unresolved',async()=>{
    const store=await start('S5');
    await answer(store,{checkId:'local_reading',value:74});
    const record=await answer(store,{checkId:'repeat_reading',value:store.state.assets.find(a=>a.id==='CRAH-1')!.value});
    expect(record.hypotheses[0].status).toBe('unresolved');
    expect(record.summary).toContain('inconclusive');
  });
  it('carries physical detail forward and supersedes old investigations in handover',async()=>{
    const store=await start();
    await answer(store,{checkId:'local_reading',value:5.5});
    await answer(store,{checkId:'physical_check',condition:'abnormal',detail:'Rattle at pump B'});
    expect(draftHandover(store.state).items.some(i=>i.summary.includes('Rattle at pump B'))).toBe(true);
    await store.command({type:'investigate',assetId:'CH-3',useModel:false});
    const items=draftHandover(store.state).items.filter(i=>i.id.startsWith('handover-investigation-'));
    expect(items).toHaveLength(1);expect(items[0].summary).toContain('not yet collected');
  });
});
