import { randomUUID } from "node:crypto";
import { fieldChecks } from "../../packages/contracts/investigation";
import type { PlantState } from "../../packages/contracts";
import type {
  Investigation,
  Answer,
} from "../../packages/contracts/investigation";

export function startInvestigation(
  state: PlantState,
  assetId: string,
  useModel: boolean,
): Investigation {
  const asset = state.assets.find((a) => a.id === assetId);
  if (
    !asset ||
    !["chiller", "crah", "cdu", "pump", "battery"].includes(asset.type)
  )
    throw Error(
      "Choose cooling equipment or a battery string for field investigation.",
    );
  const record: Investigation = {
    id: `investigation-${randomUUID()}`,
    assetId,
    createdAt: state.clock,
    updatedAt: state.clock,
    telemetry: {
      value: asset.value,
      baseline: asset.baseline,
      unit: asset.unit,
      history: [...asset.history],
      status: asset.status,
    },
    answers: [],
    nextCheck: "local_reading",
    status: "checking",
    summary: "The telemetry shows a symptom, not a confirmed cause.",
    nextAction:
      "Verify the measurement independently before selecting a response.",
    hypotheses: [],
    guidance:
      "An independent reading separates a sensor disagreement from a real equipment condition.",
    useModel,
    mode: useModel ? "planning" : "deterministic",
    model: "Evidence rules",
    calls: [],
    revision: 0,
  };
  return assessInvestigation(record);
}

/** Qualitative evidence rules. No made-up confidence scores or automatic fault closure. */
export function assessInvestigation(record: Investigation): Investigation {
  const local = record.answers.find(
    (a) => a.checkId === "local_reading",
  )?.value;
  const repeat = record.answers.find(
    (a) => a.checkId === "repeat_reading",
  )?.value;
  const physical = record.answers.find(
    (a) => a.checkId === "physical_check",
  )?.condition;
  const tolerance = Math.max(0.3, Math.abs(record.telemetry.baseline) * 0.05);
  const disagreement =
    local !== undefined && Math.abs(local - record.telemetry.value) > tolerance;
  const repeatDisagrees =
    repeat !== undefined &&
    Math.abs(repeat - record.telemetry.value) > tolerance;
  record.hypotheses = [
    {
      title: "Sensor or measurement disagreement",
      status:
        local === undefined
          ? "unresolved"
          : disagreement && repeat !== undefined && !repeatDisagrees
            ? "unresolved"
            : disagreement
              ? "supported"
              : "weakened",
      reason:
        local === undefined
          ? "No independent reading yet."
          : `${local} ${record.telemetry.unit} locally vs ${record.telemetry.value} ${record.telemetry.unit} in the telemetry snapshot. Comparison tolerance: ${tolerance.toFixed(2)} ${record.telemetry.unit}.`,
    },
    {
      title: "Physical equipment problem",
      status:
        physical === "abnormal"
          ? "supported"
          : physical === "normal"
            ? "weakened"
            : "unresolved",
      reason:
        physical === "abnormal"
          ? "The technician observed a physical abnormality; the component and cause still need diagnosis."
          : physical === "normal"
            ? "No visible or audible abnormality was observed. This does not rule out an internal problem."
            : "No conclusive physical observation yet.",
    },
    {
      title: "Real operating-condition change",
      status:
        local === undefined
          ? "unresolved"
          : !disagreement &&
              Math.abs(local - record.telemetry.baseline) > tolerance
            ? "supported"
            : disagreement
              ? "unresolved"
              : "weakened",
      reason:
        local === undefined
          ? "Needs independent verification."
          : disagreement
            ? "Resolve the conflicting measurements before inferring the process condition."
            : "Independent measurement can be compared with the equipment baseline.",
    },
  ];
  record.nextCheck =
    local === undefined
      ? "local_reading"
      : disagreement && repeat === undefined
        ? "repeat_reading"
        : physical === undefined
          ? "physical_check"
          : !disagreement && physical !== "abnormal" && repeat === undefined
            ? "repeat_reading"
            : null;
  record.status = record.nextCheck ? "checking" : "review";
  record.summary =
    local === undefined
      ? "Is this an equipment issue or a misleading sensor?"
      : disagreement
        ? repeat === undefined
          ? "The independent reading disagrees. Verify it once more before acting."
          : repeatDisagrees
            ? "Two independent readings disagree with the telemetry. A measurement issue is plausible, not proven."
            : "The repeat check conflicts with the first reading. The evidence is inconclusive."
        : physical === "abnormal"
          ? "The reading agrees and a physical abnormality was observed. Prioritize equipment inspection."
          : physical === "normal"
            ? "The reading agrees, but no physical abnormality was observed. The cause remains unconfirmed."
            : "The independent reading agrees. Check the physical condition next.";
  record.nextAction = disagreement
    ? "Have a qualified technician verify the sensor and reference instrument. Keep monitoring; do not clear the equipment warning on these readings alone."
    : physical === "abnormal"
      ? "Request a mechanical inspection with the recorded symptoms and measurements. Follow the approved procedure before any intervention."
      : "Compare flow, load, and recent maintenance with the lead technician. Keep the condition open until the cause is established.";
  record.guidance = record.nextCheck
    ? fieldChecks[record.nextCheck].help
    : record.nextAction;
  return record;
}

export function answerInvestigation(
  record: Investigation,
  answer: Answer,
  revision: number,
  clock: string,
) {
  if (record.revision !== revision)
    throw Error(
      "This investigation changed. Refresh before submitting another observation.",
    );
  if (record.status !== "checking" || record.nextCheck !== answer.checkId)
    throw Error(
      "Answer the current field check; duplicate or out-of-order answers are not accepted.",
    );
  const next = structuredClone(record);
  next.answers.push({ ...answer, ts: clock });
  next.updatedAt = clock;
  next.revision++;
  next.mode = next.useModel ? "planning" : "deterministic";
  return assessInvestigation(next);
}
