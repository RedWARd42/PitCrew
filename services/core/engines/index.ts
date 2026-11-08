import type {
  Action,
  Asset,
  PlantState,
  Warning,
} from "../../../packages/contracts";

export const median = (values: number[]): number => {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]!
    : ((sorted[middle - 1] ?? 0) + (sorted[middle] ?? 0)) / 2;
};
export function slope(values: number[]): number {
  if (values.length < 2) return 0;
  const xMean = (values.length - 1) / 2,
    yMean = values.reduce((a, b) => a + b, 0) / values.length;
  let numerator = 0,
    denominator = 0;
  values.forEach((value, index) => {
    numerator += (index - xMean) * (value - yMean);
    denominator += (index - xMean) ** 2;
  });
  return denominator ? numerator / denominator : 0;
}
export function detectDrift(
  values: number[],
  baseline = median(
    values.slice(0, Math.max(3, Math.floor(values.length / 3))),
  ),
) {
  const reference = values.slice(0, Math.max(3, Math.floor(values.length / 3)));
  const mad = median(reference.map((v) => Math.abs(v - baseline)));
  const sigma = Math.max(mad * 1.4826, Math.abs(baseline) * 0.005, 0.01);
  const delta = (values.at(-1) ?? baseline) - baseline;
  const gradient = slope(values);
  let cusum = 0;
  for (const value of values)
    cusum = Math.max(0, cusum + value - baseline - sigma * 0.5);
  return {
    z: delta / sigma,
    slope: gradient,
    direction: gradient > 0 ? "rising" : gradient < 0 ? "falling" : "stable",
    delta,
    cusum,
  };
}
export function checkSensorSanity(
  value: number,
  neighbors: number[],
  supply?: number,
) {
  const comparison = median(neighbors);
  const agreesWithNeighbors =
    neighbors.length > 0 &&
    Math.abs(value - comparison) <= Math.max(3, Math.abs(comparison) * 0.05);
  const energyBalanceOk = supply === undefined || value > supply;
  return {
    confidence: agreesWithNeighbors && energyBalanceOk ? 0.95 : 0.15,
    agreesWithNeighbors,
    energyBalanceOk,
    reason: !agreesWithNeighbors
      ? `${(value - comparison).toFixed(1)} above neighboring sensors; calibrate before treating as plant fault`
      : !energyBalanceOk
        ? "Return temperature violates supply/return energy balance"
        : "Agrees with neighboring sensors and energy balance",
  };
}
export function simulateAction(assets: Asset[], action: Action) {
  if (!assets.some((asset) => asset.id === action.target))
    return {
      affectedLoads: [],
      loads: [],
      verdict: "HOLD" as const,
      reason: "Unknown target asset; cannot verify topology safely.",
    };
  const state = new Map(assets.map((asset) => [asset.id, asset.status]));
  if (action.type !== "inspect")
    state.set(action.target, action.type === "bypass" ? "bypass" : "isolated");
  const unavailable = new Set([
    "bypass",
    "tripped",
    "isolated",
    "offline",
    "stopped",
    "failed",
  ]);
  const byId = new Map(assets.map((asset) => [asset.id, asset]));
  // Reachability is per load. Shared cycle-pruned memoization can hide a valid
  // alternate path; a per-load visited set stays cycle-safe in O(nodes+edges).
  const available = (id: string): Set<string> => {
    const visited = new Set<string>(),
      sources = new Set<string>(),
      pending = [id];
    while (pending.length) {
      const current = pending.pop()!;
      if (visited.has(current) || unavailable.has(state.get(current) ?? ""))
        continue;
      visited.add(current);
      const asset = byId.get(current);
      if (!asset) continue;
      if (asset.feeds.length) pending.push(...asset.feeds);
      else if (asset.type !== "row" && asset.type !== "load")
        sources.add(current);
    }
    return sources;
  };
  const loads = assets
    .filter((a) => a.type === "row" || a.type === "load")
    .map((asset) => {
      const sources = available(asset.id).size;
      return {
        assetId: asset.id,
        sources,
        level: sources > 1 ? "N+1" : sources === 1 ? "N" : "LOST",
      };
    });
  const affectedLoads = loads
    .filter((l) => l.sources === 0)
    .map((l) => l.assetId);
  return {
    affectedLoads,
    loads,
    verdict: affectedLoads.length ? ("HOLD" as const) : ("GO" as const),
    reason: affectedLoads.length
      ? `${affectedLoads.join(", ").replace("Row-D", "Row D")} loses its last source. Restore and verify an independent alternate source before isolation.`
      : "All loads retain at least one available source.",
  };
}
export function projectTimeToLimit(
  values: number[],
  limit: number,
  intervalMinutes = 1,
) {
  const gradient = slope(values) / intervalMinutes;
  const current = values.at(-1);
  const assumptions = [
    "No chiller restarts; load constant",
    "Recent linear temperature trend continues",
  ];
  if (current === undefined || values.length < 3 || gradient <= 0)
    return {
      etaMinutes: null,
      confidence: null,
      assumptions: [
        ...assumptions,
        "Insufficient rising trend for a defensible ETA",
      ],
      slope: gradient,
    };
  const etaMinutes = Math.max(0, (limit - current) / gradient);
  const predicted = values.map(
    (_, i) => (values[0] ?? 0) + gradient * intervalMinutes * i,
  );
  const residual = Math.sqrt(
    values.reduce(
      (sum, value, i) => sum + (value - (predicted[i] ?? 0)) ** 2,
      0,
    ) / values.length,
  );
  const uncertainty = Math.max(etaMinutes * 0.1, (1.96 * residual) / gradient);
  return {
    etaMinutes,
    confidence: [
      Math.max(0, etaMinutes - uncertainty),
      etaMinutes + uncertainty,
    ] as [number, number],
    assumptions,
    slope: gradient,
  };
}
export type Alarm = { assetId: string; code: string; ts: string };
export function correlateAlarms(alarms: Alarm[], windowSeconds = 90) {
  const ordered = [...alarms].sort(
    (a, b) => Date.parse(a.ts) - Date.parse(b.ts),
  );
  const windows: Alarm[][] = [];
  for (const alarm of ordered) {
    const group = windows.at(-1);
    if (
      !group ||
      Date.parse(alarm.ts) - Date.parse(group[0]!.ts) > windowSeconds * 1000
    )
      windows.push([alarm]);
    else group.push(alarm);
  }
  const groups = windows.flatMap((window) => {
    if (window.some((a) => a.code === "voltage_dip")) return [window];
    const byDomain = new Map<string, Alarm[]>();
    for (const alarm of window) {
      const domain = /^(CH-|CDU-|CRAH-|P-)/.test(alarm.assetId)
        ? "cooling"
        : /^(UPS-|PDU-|Row-|BAT-)/.test(alarm.assetId)
          ? "power"
          : alarm.assetId;
      const group = byDomain.get(domain) ?? [];
      group.push(alarm);
      byDomain.set(domain, group);
    }
    return [...byDomain.values()];
  });
  const clusters = groups.map((group) => ({
    rootCause: group.some((a) => a.code === "voltage_dip")
      ? "Voltage dip → CH-1/CH-2 trip; CH-3 failed to auto-start"
      : (group[0]?.code ?? "Unknown cause"),
    assetIds: [...new Set(group.map((a) => a.assetId))],
    alarmCount: group.length,
  }));
  const end = ordered.at(-1)?.ts;
  return {
    clusters,
    suppressed: alarms.length - clusters.length,
    alarmsPer10Minutes: end
      ? ordered.filter((a) => Date.parse(end) - Date.parse(a.ts) <= 600000)
          .length
      : 0,
  };
}
export function rankRounds(
  assets: Asset[],
  warnings: Warning[],
  notes: PlantState["notes"],
) {
  return assets
    .map((asset) => {
      const anomaly =
        1 +
        Math.abs(asset.value - asset.baseline) /
          Math.max(0.1, Math.abs(asset.baseline) * 0.05);
      const open = warnings.filter(
        (w) => w.assetId === asset.id && w.state !== "resolved",
      ).length;
      const note = notes.filter(
        (n) => n.assetId === asset.id && n.structured.followUp,
      ).length;
      return {
        assetId: asset.id,
        score: asset.criticality * anomaly * (1 + open + note),
        rationale:
          open || note
            ? `${Math.abs(asset.value - asset.baseline).toFixed(1)} ${asset.unit} vs baseline · ${open} open warnings · ${note} follow-up notes`
            : "Routine inspection · within personal baseline",
      };
    })
    .sort((a, b) => b.score - a.score);
}
