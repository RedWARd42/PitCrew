import { z } from "zod";
export const CheckId = z.enum([
  "local_reading",
  "physical_check",
  "repeat_reading",
]);
export const FieldAnswer = z
  .object({
    checkId: CheckId,
    value: z.number().finite().optional(),
    condition: z.enum(["abnormal", "normal", "uncertain"]).optional(),
    detail: z.string().trim().max(1000).optional(),
  })
  .superRefine((answer, ctx) => {
    if (
      answer.checkId === "physical_check"
        ? !answer.condition || answer.value !== undefined
        : answer.value === undefined || answer.condition !== undefined
    )
      ctx.addIssue({
        code: "custom",
        message:
          "Provide a numeric reading or a physical condition matching this check.",
      });
  });
export const InvestigationSchema = z.object({
  id: z.string(),
  assetId: z.string(),
  createdAt: z.string(),
  updatedAt: z.string(),
  telemetry: z.object({
    value: z.number(),
    baseline: z.number(),
    unit: z.string(),
    history: z.array(z.number()),
    status: z.string(),
  }),
  answers: z.array(
    z.object({
      checkId: CheckId,
      value: z.number().optional(),
      condition: z.enum(["abnormal", "normal", "uncertain"]).optional(),
      detail: z.string().max(1000).optional(),
      ts: z.string(),
    }),
  ),
  nextCheck: CheckId.nullable(),
  status: z.enum(["checking", "review"]),
  summary: z.string(),
  nextAction: z.string(),
  hypotheses: z.array(
    z.object({
      title: z.string(),
      status: z.enum(["supported", "weakened", "unresolved"]),
      reason: z.string(),
    }),
  ),
  guidance: z.string(),
  useModel: z.boolean(),
  mode: z.enum(["planning", "live", "deterministic", "fallback"]),
  model: z.string(),
  calls: z.array(z.object({ tool: z.string(), summary: z.string() })),
  revision: z.number().int().nonnegative(),
});
export type Investigation = z.infer<typeof InvestigationSchema>;
export type Answer = z.infer<typeof FieldAnswer>;

export const fieldChecks = {
  local_reading: {
    title: "Compare an independent reading",
    question:
      "What does the independent local gauge or reference instrument read?",
    help: "Use the same metric and unit shown below. Do not copy the dashboard value or use a display fed by the same sensor.",
    kind: "number",
  },
  physical_check: {
    title: "Check the equipment in person",
    question:
      "From a safe observation point, is there unusual noise, vibration, leakage, or restricted airflow?",
    help: "Observe only. Do not open enclosures, touch moving equipment, or change controls.",
    kind: "condition",
  },
  repeat_reading: {
    title: "Repeat the independent measurement",
    question:
      "After rechecking the instrument and measurement point, what does it read?",
    help: "Use the same independent instrument and units. This cross-check is not a calibrated time-to-failure prediction.",
    kind: "number",
  },
} as const;
