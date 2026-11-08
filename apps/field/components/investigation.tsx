"use client";
import { useState } from "react";
import Link from "next/link";
import {
  ArrowRight,
  Check,
  CircleHelp,
  GitBranch,
  LoaderCircle,
  Search,
  Smartphone,
  TriangleAlert,
} from "lucide-react";
import { motion, useReducedMotion } from "framer-motion";
import type { Command, PlantState } from "../../../packages/contracts";
import type { Investigation as Record } from "../../../packages/contracts/investigation";
import { fieldChecks } from "../../../packages/contracts/investigation";

type Send = (command: Command, message?: string) => Promise<PlantState | null>;
export function InvestigationLauncher({ state }: { state: PlantState }) {
  const assets = state.assets
    .filter((a) =>
      ["chiller", "crah", "cdu", "battery", "pump"].includes(a.type),
    )
    .sort(
      (a, b) =>
        Math.abs(b.value - b.baseline) / Math.max(0.1, Math.abs(b.baseline)) -
        Math.abs(a.value - a.baseline) / Math.max(0.1, Math.abs(a.baseline)),
    )
    .slice(0, 3);
  return (
    <section className="diagnosis-launcher">
      <div>
        <Search size={22} />
        <h2>Find out what’s actually wrong.</h2>
        <p>Compare the signal with evidence from the floor.</p>
      </div>
      <div className="diagnosis-assets">
        {assets.map((a) => (
          <Link href={`/investigate/${a.id}`} key={a.id}>
            <span>
              <strong>{a.name}</strong>
              <small>
                {a.value.toFixed(1)} {a.unit} · baseline {a.baseline}
              </small>
            </span>
            <ArrowRight size={17} />
          </Link>
        ))}
      </div>
    </section>
  );
}
export default function Investigation({
  state,
  assetId,
  send,
  busy,
}: {
  state: PlantState;
  assetId: string;
  send: Send;
  busy: boolean;
}) {
  const asset = state.assets.find((a) => a.id === assetId);
  const record = state.investigations
    .filter((i) => i.assetId === assetId)
    .at(-1);
  const [useModel, setUseModel] = useState(true);
  const [value, setValue] = useState("");
  const [detail, setDetail] = useState("");
  const [condition, setCondition] = useState<
    "normal" | "abnormal" | "uncertain" | ""
  >("");
  const reduced = useReducedMotion();
  if (!asset)
    return (
      <div className="card next-task">
        <h2>Equipment not found.</h2>
        <Link href="/">Return to the decision room</Link>
      </div>
    );
  const start = () =>
    send(
      { type: "investigate", assetId, useModel: record?.useModel ?? useModel },
      "Investigation started",
    );
  const active = record?.status === "checking";
  const check = record?.nextCheck ? fieldChecks[record.nextCheck] : null;
  const planning = record?.mode === "planning";
  const warnings = state.warnings.filter(
    (w) => w.assetId === assetId && w.state !== "resolved",
  );
  return (
    <div className="diagnosis">
      <div className="diagnosis-heading">
        <div>
          <Link href={`/a/${assetId}`}>
            {assetId} · {asset.zone}
          </Link>
          <h2>{asset.name}</h2>
        </div>
        <div className="diagnosis-measurement">
          <strong>
            {asset.value.toFixed(1)} <small>{asset.unit}</small>
          </strong>
          <span>Current telemetry</span>
        </div>
      </div>
      {!record ? (
        <section className="diagnosis-start">
          <div className="diagnosis-symbol">
            <Search size={30} />
          </div>
          <h2>A signal isn’t a diagnosis.</h2>
          <p>
            Start with competing explanations. Gather independent evidence on
            your phone, then see which explanation holds up.
          </p>
          <div className="diagnosis-preview">
            <span>Sensor disagreement</span>
            <span>Physical fault</span>
            <span>Operating change</span>
          </div>
          <label className="diagnosis-model">
            <input
              type="checkbox"
              checked={useModel}
              onChange={(e) => setUseModel(e.target.checked)}
            />
            Use Nemotron to investigate evidence and select follow-up checks
            (sends demo evidence to NVIDIA)
          </label>
          <button
            className="button primary"
            disabled={busy}
            onClick={() => void start()}
          >
            {busy ? "Starting…" : "Start investigation"}
            <ArrowRight size={17} />
          </button>
          <small>Observation only. No equipment controls are connected.</small>
        </section>
      ) : (
        <>
          <div className="diagnosis-status">
            <span className={`diagnosis-mode ${record.mode}`}>
              {planning ? (
                <LoaderCircle size={15} className="diagnosis-spin" />
              ) : (
                <GitBranch size={15} />
              )}{" "}
              {planning
                ? "Nemotron is inspecting evidence"
                : record.mode === "live"
                  ? "Nemotron · live tools"
                  : record.mode === "fallback"
                    ? "Evidence rules · model unavailable"
                    : "Evidence rules"}
            </span>
            <span>{record.answers.length} field observations</span>
          </div>
          {(asset.value !== record.telemetry.value ||
            asset.status !== record.telemetry.status) && (
            <div className="alert">
              <TriangleAlert size={16} />
              Telemetry has changed. This investigation compares against its
              starting snapshot: {record.telemetry.value}{" "}
              {record.telemetry.unit}.
            </div>
          )}
          <div className="diagnosis-layout">
            <section className="diagnosis-main">
              <div className="diagnosis-assessment">
                <span className="diagnosis-label">Working assessment</span>
                <h2>{record.summary}</h2>
                <p>
                  These are evidence-based possibilities, not a confirmed root
                  cause.
                </p>
              </div>
              <div className="diagnosis-hypotheses">
                {record.hypotheses.map((h) => (
                  <article key={h.title}>
                    <div>
                      <strong>{h.title}</strong>
                      <span className={h.status}>
                        {h.status === "supported"
                          ? "Evidence supports"
                          : h.status === "weakened"
                            ? "Less supported"
                            : "Unresolved"}
                      </span>
                    </div>
                    <p>{h.reason}</p>
                  </article>
                ))}
              </div>
              <motion.div
                key={`${record.nextCheck}-${record.status}`}
                initial={{ opacity: reduced ? 1 : 0 }}
                animate={{ opacity: 1 }}
                transition={{ duration: 0.16 }}
                className="diagnosis-check"
              >
                {active && check ? (
                  <>
                    <div className="diagnosis-check-title">
                      <Smartphone size={20} />
                      <h3>{check.title}</h3>
                    </div>
                    <p>{check.question}</p>
                    <small>{check.help}</small>
                    <form
                      onSubmit={async (e) => {
                        e.preventDefault();
                        if (!record.nextCheck) return;
                        const answer =
                          record.nextCheck === "physical_check"
                            ? {
                                checkId: record.nextCheck,
                                detail: detail.trim() || undefined,
                                condition: condition as
                                  "normal" | "abnormal" | "uncertain",
                              }
                            : {
                                checkId: record.nextCheck,
                                value: Number(value),
                              };
                        if (
                          await send(
                            {
                              type: "field_answer",
                              investigationId: record.id,
                              revision: record.revision,
                              answer,
                            },
                            "Evidence saved; assessment updated",
                          )
                        ) {
                          setValue("");
                          setCondition("");
                          setDetail("");
                        }
                      }}
                    >
                      {check.kind === "number" ? (
                        <label>
                          Independent reading ({record.telemetry.unit})
                          <input
                            aria-label="Independent reading"
                            inputMode="decimal"
                            value={value}
                            onChange={(e) => setValue(e.target.value)}
                            placeholder="Enter what you measure"
                            required
                          />
                        </label>
                      ) : (
                        <fieldset>
                          <legend>What did you observe?</legend>
                          {(
                            [
                              ["abnormal", "Something abnormal"],
                              ["normal", "No abnormality observed"],
                              ["uncertain", "Unable to verify"],
                            ] as const
                          ).map(([v, label]) => (
                            <label
                              key={v}
                              className={condition === v ? "selected" : ""}
                            >
                              <input
                                type="radio"
                                name="condition"
                                value={v}
                                checked={condition === v}
                                onChange={() => setCondition(v)}
                              />
                              {label}
                            </label>
                          ))}
                        </fieldset>
                      )}
                      {check.kind === "condition" && (
                        <label style={{ marginTop: 16 }}>
                          What did you notice? (optional)
                          <textarea
                            aria-label="Field detail"
                            value={detail}
                            maxLength={1000}
                            onChange={(e) => setDetail(e.target.value)}
                            rows={3}
                            placeholder="For example: rattling near pump B under load"
                          />
                        </label>
                      )}
                      <button
                        className="button primary"
                        disabled={
                          busy ||
                          planning ||
                          (check.kind === "number"
                            ? !value.trim() || !Number.isFinite(Number(value))
                            : !condition)
                        }
                      >
                        {planning
                          ? "Waiting for investigator…"
                          : busy
                            ? "Saving…"
                            : "Submit evidence"}
                        <ArrowRight size={16} />
                      </button>
                    </form>
                  </>
                ) : (
                  <>
                    <div className="diagnosis-check-title">
                      <Check size={20} />
                      <h3>Ready for technical review</h3>
                    </div>
                    <p>{record.nextAction}</p>
                    <div className="diagnosis-actions">
                      {warnings
                        .filter((w) => w.state !== "owned")
                        .map((w) => (
                          <button
                            key={w.id}
                            className="button primary"
                            disabled={busy}
                            onClick={() =>
                              void send(
                                { type: "take_ownership", warningId: w.id },
                                "Follow-up accepted",
                              )
                            }
                          >
                            Take this follow-up
                            <Check size={16} />
                          </button>
                        ))}
                      <Link href="/handover" className="button secondary">
                        Carry into handover
                        <ArrowRight size={16} />
                      </Link>
                    </div>
                    <small>
                      Warnings stay open. A qualified technician determines the
                      intervention.
                    </small>
                    <button
                      className="text-link"
                      style={{ marginTop: 18 }}
                      disabled={busy || planning}
                      onClick={() => void start()}
                    >
                      Start a new investigation <ArrowRight size={14} />
                    </button>
                  </>
                )}
              </motion.div>
            </section>
            <aside className="diagnosis-context">
              <div className="diagnosis-agent">
                <GitBranch size={20} />
                <h3>
                  {planning ? "Following the evidence…" : "Why this next step?"}
                </h3>
                <p>
                  {planning
                    ? "The investigator can retrieve trends, peer readings, notes, active work, and approved procedures. You can keep using the rest of the app."
                    : record.guidance}
                </p>
                {record.mode === "live" && <small>{record.model}</small>}
                <details>
                  <summary>
                    Evidence tools · {record.calls.length} calls
                  </summary>
                  {record.calls.length ? (
                    record.calls.map((call, i) => (
                      <p key={i}>
                        <Check size={12} />
                        {call.summary}
                      </p>
                    ))
                  ) : (
                    <p>No live model tool calls recorded.</p>
                  )}
                </details>
              </div>
              <EvidenceLog record={record} />
              <Link href="/" className="diagnosis-back">
                Decision room
                <ArrowRight size={15} />
              </Link>
            </aside>
          </div>
        </>
      )}
    </div>
  );
}
function EvidenceLog({ record }: { record: Record }) {
  return (
    <div className="diagnosis-log">
      <h3>Evidence collected</h3>
      <article>
        <span>Telemetry snapshot</span>
        <strong>
          {record.telemetry.value} {record.telemetry.unit}
        </strong>
        <small>
          Baseline {record.telemetry.baseline} {record.telemetry.unit}
        </small>
      </article>
      {record.answers.map((a, i) => (
        <article key={a.checkId}>
          <span>
            {i + 1}. {fieldChecks[a.checkId].title}
          </span>
          <strong>
            {a.value !== undefined
              ? `${a.value} ${record.telemetry.unit}`
              : a.condition === "abnormal"
                ? "Abnormality observed"
                : a.condition === "normal"
                  ? "No abnormality observed"
                  : "Unable to verify"}
          </strong>
          {a.detail && <p style={{ fontSize: 12, marginTop: 8 }}>{a.detail}</p>}
          <small>
            Field observation ·{" "}
            {new Date(a.ts).toLocaleTimeString("en-US", {
              hour: "2-digit",
              minute: "2-digit",
              timeZone: "America/Chicago",
            })}
          </small>
        </article>
      ))}
      {!record.answers.length && (
        <p>
          <CircleHelp size={15} /> No independent evidence yet.
        </p>
      )}
    </div>
  );
}
