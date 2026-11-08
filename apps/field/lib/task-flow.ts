import type { PlantState } from "../../../packages/contracts";
import { rankRounds } from "../../../services/core/engines";

export function receivedHandover(state: PlantState) {
  return (
    state.audit.some((item) => item.action === "handover.received") ||
    (state.handover.length > 0 &&
      state.handover.every((item) => item.confirmed))
  );
}

export function inspectionProgress(state: PlantState, assetId: string) {
  let reading = -1,
    observation = -1,
    completion = -1;
  state.audit.forEach((item, index) => {
    if (item.action === "reading.new" && item.detail.startsWith(`${assetId}: `))
      reading = index;
    if (item.action === "note.created" && item.detail === assetId)
      observation = index;
    if (
      item.action === "inspection.completed" &&
      item.detail.startsWith(`${assetId}: `)
    )
      completion = index;
  });
  const warnings = state.warnings.filter(
    (item) => item.assetId === assetId && item.state !== "resolved",
  );
  return {
    reading: reading > completion,
    observation: observation > reading && reading > completion,
    owned: warnings.every(
      (item) => item.state === "owned",
    ),
    completed: completion >= 0 && completion > reading,
    readingAudit: reading >= 0 ? state.audit[reading] : undefined,
    warnings,
  };
}
export function roundTasks(state: PlantState) {
  return rankRounds(state.assets, state.warnings, state.notes).map((rank) => ({
    asset: state.assets.find((asset) => asset.id === rank.assetId)!,
    reason: rank.rationale
      .replace("1 open warnings", "1 open warning")
      .replace("1 follow-up notes", "1 follow-up note")
      .replace("personal baseline", "equipment baseline"),
    progress: inspectionProgress(state, rank.assetId),
  }));
}
