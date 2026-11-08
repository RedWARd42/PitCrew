import { describe, expect, it } from "vitest";
import { PlantStore } from "../services/core/store";
import { decisionBrief, rehearse } from "../services/core/decisions";
import { POST } from "../apps/field/app/api/decisions/route";

describe("decision room", () => {
  it("rehearses loss of the last source without mutating plant state", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S2" });
    const before = structuredClone(store.state);
    const result = rehearse(store.state, {
      type: "open_breaker",
      target: "PDU-4",
    });
    expect(result.verdict).toBe("HOLD");
    expect(result.loads).toContainEqual(
      expect.objectContaining({ assetId: "Row-D", before: "N", level: "LOST" }),
    );
    expect(store.state).toEqual(before);
  });
  it("retains an alternate path at baseline but does not authorize work", () => {
    const result = rehearse(new PlantStore().state, {
      type: "open_breaker",
      target: "PDU-4",
    });
    expect(result.verdict).toBe("GO");
    expect(result.loads[0].level).toBe("N");
    expect(result.advisoryOnly).toBe(true);
  });
  it("updates ownership gaps and excludes resolved commitments", async () => {
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S1" });
    const brief = decisionBrief(store.state);
    expect(brief.priorities[0].missing).toContain("Owner acceptance");
    await store.command({
      type: "ack",
      warningId: brief.priorities[0].id,
      readback: "I will inspect pump B by 02:30.",
    });
    expect(decisionBrief(store.state).unaccepted).toBe(0);
    store.state.warnings[0].state = "resolved";
    expect(decisionBrief(store.state).priorities).toHaveLength(0);
  });
  it("rejects malformed, unsupported and unknown rehearsal requests", async () => {
    for (const body of [
      "{",
      JSON.stringify({ type: "reset", target: "PDU-4" }),
    ]) {
      const response = await POST(
        new Request("http://localhost/api/decisions", { method: "POST", body }),
      );
      expect(response.status).toBe(400);
    }
    for (const target of ["unknown", "CH-3"]) {
      const response = await POST(
        new Request("http://localhost/api/decisions", {
          method: "POST",
          body: JSON.stringify({ type: "stop", target }),
        }),
      );
      expect(response.status).toBe(422);
    }
  });
});
