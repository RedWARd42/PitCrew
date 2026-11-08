import { describe, it, expect } from "vitest";
import fc from "fast-check";
import {
  checkSensorSanity,
  correlateAlarms,
  detectDrift,
  projectTimeToLimit,
  rankRounds,
  simulateAction,
} from "./index";
import {
  applyScenario,
  createInitialState,
  scenarioAlarms,
  random,
} from "../../sim";

describe("deterministic plant engines", () => {
  it("traverses generic upstream chains and counts independent sources rather than duplicate paths", () => {
    const base = createInitialState().assets[0]!;
    const make = (id: string, feeds: string[] = [], type = "supply") => ({
      ...base,
      id,
      name: id,
      type,
      feeds,
    });
    const assets = [
      make("utility-east"),
      make("utility-west"),
      make("switch-east", ["utility-east"]),
      make("switch-west", ["utility-west"]),
      make("hall-load", ["switch-east", "switch-west"], "load"),
    ];
    expect(
      simulateAction(assets, { type: "inspect", target: "hall-load" }).loads[0]
        ?.sources,
    ).toBe(2);
    expect(
      simulateAction(assets, { type: "stop", target: "utility-east" }).loads[0],
    ).toMatchObject({ sources: 1, level: "N" });
    assets.find((asset) => asset.id === "utility-west")!.status = "offline";
    expect(
      simulateAction(assets, { type: "stop", target: "utility-east" }).verdict,
    ).toBe("HOLD");
    assets.find((asset) => asset.id === "utility-west")!.status = "online";
    assets.find((asset) => asset.id === "switch-west")!.feeds = [
      "utility-east",
    ];
    expect(
      simulateAction(assets, { type: "inspect", target: "hall-load" }).loads[0]
        ?.sources,
    ).toBe(1);
  });
  it("finds a valid alternate path through a cycle independent of load traversal order", () => {
    const base = createInitialState().assets[0]!;
    const make = (id: string, feeds: string[] = [], type = "supply") => ({
      ...base,
      id,
      name: id,
      type,
      feeds,
    });
    const assets = [
      make("source"),
      make("a", ["b", "source"]),
      make("b", ["a"]),
      make("load-first", ["a"], "load"),
      make("load-second", ["b"], "load"),
    ];
    const forward = simulateAction(assets, {
      type: "inspect",
      target: "source",
    });
    expect(forward.verdict).toBe("GO");
    expect(forward.loads.map((load) => load.sources)).toEqual([1, 1]);
    const reversed = simulateAction([...assets].reverse(), {
      type: "inspect",
      target: "source",
    });
    expect(reversed.loads.map((load) => load.sources)).toEqual([1, 1]);
    expect(
      simulateAction(assets, {
        type: "stop",
        target: "source",
      }).affectedLoads.sort(),
    ).toEqual(["load-first", "load-second"]);
  });
  it("scales the projected ETA by the measurement interval and clamps an exceeded limit to zero", () => {
    expect(projectTimeToLimit([2, 4, 6], 10, 2).etaMinutes).toBeCloseTo(4);
    expect(projectTimeToLimit([2, 4, 6], 5, 2).etaMinutes).toBe(0);
  });
  it("detects +1.5°F drift above the unit baseline", () => {
    const state = createInitialState();
    applyScenario(state, "S1");
    const asset = state.assets.find((a) => a.id === "CH-3")!;
    const drift = detectDrift(asset.history, asset.baseline);
    expect(drift.delta).toBe(1.5);
    expect(drift.z).toBeGreaterThan(3);
    expect(drift.direction).toBe("rising");
    expect(drift.cusum).toBeGreaterThan(0);
    expect(rankRounds(state.assets, [], state.notes)[0]?.assetId).toBe("CH-3");
  });
  it("blocks last-feed loss and permits the same isolation with alternate feed available", () => {
    const state = createInitialState();
    const action = { type: "open_breaker" as const, target: "PDU-4" };
    expect(simulateAction(state.assets, action).verdict).toBe("GO");
    applyScenario(state, "S2");
    expect(simulateAction(state.assets, action).affectedLoads).toEqual([
      "Row-D",
    ]);
    expect(simulateAction(state.assets, action).reason).toContain(
      "last source",
    );
  });
  it("never gains a source when a feed is removed (property test)", () => {
    fc.assert(
      fc.property(
        fc.boolean(),
        fc.boolean(),
        (firstAvailable, secondAvailable) => {
          const state = createInitialState();
          state.assets.find((a) => a.id === "UPS-1")!.status = firstAvailable
            ? "online"
            : "offline";
          state.assets.find((a) => a.id === "UPS-2")!.status = secondAvailable
            ? "online"
            : "offline";
          const before = simulateAction(state.assets, {
            type: "inspect",
            target: "Row-D",
          }).loads[0]!.sources;
          const after = simulateAction(state.assets, {
            type: "open_breaker",
            target: "PDU-4",
          }).loads[0]!.sources;
          expect(after).toBeLessThanOrEqual(before);
          expect(after).toBeGreaterThanOrEqual(0);
        },
      ),
    );
  });
  it("does not mutate source state during impact simulation", () => {
    const state = createInitialState();
    const before = structuredClone(state.assets);
    simulateAction(state.assets, { type: "bypass", target: "UPS-2" });
    expect(state.assets).toEqual(before);
  });
  it("fails closed when a compiled action names an unknown target", () => {
    expect(
      simulateAction(createInitialState().assets, {
        type: "open_breaker",
        target: "hallucinated-breaker",
      }).verdict,
    ).toBe("HOLD");
  });
  it("terminates for a topology with a cycle and marks the load unavailable", () => {
    const state = createInitialState();
    state.assets.find((a) => a.id === "PDU-4")!.feeds = ["Row-D"];
    state.assets.find((a) => a.id === "UPS-2")!.status = "offline";
    expect(
      simulateAction(state.assets, { type: "inspect", target: "Row-D" })
        .verdict,
    ).toBe("HOLD");
  });
  it("suppresses a lying sensor and rejects impossible energy balance", () => {
    expect(checkSensorSanity(82, [74, 74.1, 73.9], 48).confidence).toBeLessThan(
      0.5,
    );
    expect(checkSensorSanity(74, [74, 74.1], 48).confidence).toBeGreaterThan(
      0.9,
    );
    expect(checkSensorSanity(40, [40, 40.1], 48).energyBalanceOk).toBe(false);
  });
  it("correlates the 47-alarm cascade and projects a 14-minute restart limit", () => {
    const state = createInitialState();
    applyScenario(state, "S3");
    const alarms = correlateAlarms(scenarioAlarms(state));
    expect(alarms.clusters).toHaveLength(1);
    expect(alarms.suppressed).toBe(46);
    expect(alarms.clusters[0]?.rootCause).toContain("Voltage dip");
    const eta = projectTimeToLimit(
      state.assets.find((a) => a.id === "CDU-1")!.history,
      62,
    );
    expect(eta.etaMinutes).toBeCloseTo(14);
    expect(eta.confidence?.[0]).toBeLessThan(14);
    expect(eta.confidence?.[1]).toBeGreaterThan(14);
    expect(projectTimeToLimit([3, 2, 1], 62).etaMinutes).toBeNull();
  });
  it("keeps separate alarms outside the correlation time window", () => {
    expect(
      correlateAlarms([
        { assetId: "a", code: "one", ts: "2026-01-01T00:00:00Z" },
        { assetId: "b", code: "two", ts: "2026-01-01T00:02:00Z" },
      ]).clusters,
    ).toHaveLength(2);
  });
  it("keeps unrelated domains separate without an upstream common cause", () => {
    expect(
      correlateAlarms([
        { assetId: "CH-1", code: "trip", ts: "2026-01-01T00:00:00Z" },
        { assetId: "BAT-3", code: "impedance", ts: "2026-01-01T00:00:01Z" },
      ]).clusters,
    ).toHaveLength(2);
  });
  it("replays identical seeds, and handles empty telemetry without false urgency", () => {
    const a = random(42),
      b = random(42);
    expect(Array.from({ length: 10 }, a)).toEqual(
      Array.from({ length: 10 }, b),
    );
    expect(createInitialState()).toEqual(createInitialState());
    expect(projectTimeToLimit([], 62).etaMinutes).toBeNull();
    expect(detectDrift([]).delta).toBe(0);
  });
});
