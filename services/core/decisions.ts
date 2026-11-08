import type { Action, PlantState } from "../../packages/contracts";
import { simulateAction } from "./engines";

/** A snapshot-derived briefing. No model is allowed to change topology verdicts. */
export function decisionBrief(state: PlantState) {
  const open = state.warnings.filter((w) => w.state !== "resolved");
  const priorities = open
    .map((w) => {
      const asset = state.assets.find((a) => a.id === w.assetId)!;
      const minutes = Math.ceil(
        (Date.parse(w.dueAt) - Date.parse(state.clock)) / 60000,
      );
      const notes = state.notes.filter((n) => n.assetId === w.assetId);
      return {
        ...w,
        assetName: asset?.name ?? w.assetId,
        minutes,
        ownerName:
          state.people.find((p) => p.id === w.ownerId)?.name ?? w.ownerId,
        score:
          (w.severity === "critical" ? 100 : 40) +
          (minutes <= 0 ? 30 : 0) +
          (w.state !== "owned" ? 15 : 0),
        evidenceCount: w.evidence.length + notes.length,
        missing: [
          w.state === "owned" ? null : "Owner acceptance",
          notes.some((n) => n.ts >= w.createdAt)
            ? null
            : "Fresh field observation",
        ].filter((s): s is string => Boolean(s)),
        notes: notes.slice(-3),
      };
    })
    .sort(
      (a, b) =>
        b.score - a.score || a.minutes - b.minutes || a.id.localeCompare(b.id),
    );
  const topology = simulateAction(state.assets, {
    type: "inspect",
    target: state.assets[0]?.id ?? "",
  });
  return {
    asOf: state.clock,
    priorities,
    topology: topology.loads,
    unaccepted: open.filter((w) => w.state !== "owned").length,
    overdue: open.filter((w) => Date.parse(w.dueAt) <= Date.parse(state.clock))
      .length,
    handoverPending: state.handover.filter((h) => !h.confirmed).length,
    incidents: state.incidents,
    provenance: "Deterministic prioritization · severity, deadline, ownership",
  };
}
export type DecisionBrief = ReturnType<typeof decisionBrief>;

export function rehearse(state: PlantState, action: Action) {
  const target = state.assets.find((a) => a.id === action.target);
  if (!target) throw new Error("Unknown equipment");
  if (!["ups", "pdu"].includes(target.type))
    throw new Error("Rehearsal supports modeled power equipment only");
  const before = simulateAction(state.assets, {
    type: "inspect",
    target: action.target,
  });
  const after = simulateAction(state.assets, action);
  return {
    asOf: state.clock,
    action,
    verdict: after.verdict,
    reason: after.reason,
    loads: after.loads.map((load) => ({
      ...load,
      before:
        before.loads.find((l) => l.assetId === load.assetId)?.level ??
        "UNKNOWN",
    })),
    assumptions: [
      "Snapshot only; recheck before work.",
      "Source reachability does not prove capacity or electrical independence.",
      "Permits, local indications, and approved procedures remain required.",
    ],
    advisoryOnly: true as const,
  };
}
export type Rehearsal = ReturnType<typeof rehearse>;
