"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import {
  ArrowRight,
  ArrowUpRight,
  BookOpen,
  Check,
  CheckCheck,
  ChevronRight,
  Clock3,
  Layers3,
  MapPin,
  MessageCircle,
  Route,
  ShieldAlert,
  ShieldCheck,
  TriangleAlert,
} from "lucide-react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import type { Command, PlantState } from "../../../packages/contracts";
import {
  inspectionProgress,
  roundTasks,
  receivedHandover,
} from "../lib/task-flow";

type Send = (command: Command, message?: string) => Promise<PlantState | null>;
type Open = (
  kind: "reading" | "note" | "ack" | "confirm" | "override" | "auth",
  id: string,
  value?: string,
) => void;
function localTime(ts: string) {
  return new Date(ts).toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "America/Chicago",
  });
}
export function ShiftJourney({
  state,
  current,
}: {
  state: PlantState;
  current: "start" | "rounds" | "handover";
}) {
  const started = receivedHandover(state);
  return (
    <nav className="shift-journey" aria-label="Shift journey">
      {[
        {
          id: "start",
          href: "/start",
          label: "Start my shift",
          detail: started ? "Handover reviewed" : "Receive the handover",
          done: started,
        },
        {
          id: "rounds",
          href: "/rounds",
          label: "Work my rounds",
          detail: "Inspect, record, follow through",
          done: false,
        },
        {
          id: "handover",
          href: "/handover",
          label: "Hand over my shift",
          detail: "Pass on the commitments",
          done: false,
        },
      ].map((item, i) => (
        <Link
          key={item.id}
          href={item.href}
          className={`journey-link ${current === item.id ? "current" : ""} ${item.done ? "complete" : ""}`}
          aria-current={current === item.id ? "step" : undefined}
        >
          <span>
            {item.done ? <Check size={16} /> : String(i + 1).padStart(2, "0")}
          </span>
          <div>
            <strong>{item.label}</strong>
            <small>{item.detail}</small>
          </div>
          <ChevronRight size={15} />
        </Link>
      ))}
    </nav>
  );
}
export function TaskHome({ state }: { state: PlantState }) {
  const tasks = roundTasks(state),
    next = tasks.find((task) => !task.progress.completed),
    pending = receivedHandover(state)
      ? []
      : state.handover.filter((item) => !item.confirmed),
    incident = state.incidents[0],
    hold = state.runs.find((run) => !run.completed && run.verdict === "HOLD");
  const open = state.warnings.filter((item) => item.state !== "resolved");
  return (
    <div className="task-home">
      <ShiftJourney
        state={state}
        current={pending.length ? "start" : "rounds"}
      />
      {incident && (
        <Link href="/incident" className="incident-banner">
          <ShieldAlert />
          <div>
            <strong>Respond to {incident.title.toLowerCase()}</strong>
            <p>
              ≈{incident.etaMinutes?.toFixed(0) ?? "—"} minutes to restart limit
              · Open the emergency procedure
            </p>
          </div>
          <ArrowRight />
        </Link>
      )}
      {hold && (
        <Link
          href={`/procedures?procedure=${hold.procedureId}&asset=${hold.assetId}`}
          className="incident-banner"
        >
          <ShieldAlert />
          <div>
            <strong>Maintenance is on HOLD at {hold.assetId}</strong>
            <p>Review the topology conflict before continuing this job.</p>
          </div>
          <ArrowRight />
        </Link>
      )}
      <div className="task-layout">
        <div>
          {pending.length > 0 && (
            <section className="card next-task intake-prompt">
              <div className="task-kicker">
                <CheckCheck size={16} />
                START WITH THE HANDOVER
              </div>
              <h2>Before you head onto the floor.</h2>
              <p>
                {pending.length} inherited{" "}
                {pending.length === 1 ? "item needs" : "items need"} your
                read-back. Start with “{pending[0].summary}”
              </p>
              <Link className="button primary" href="/start">
                Start my shift <ArrowRight size={17} />
              </Link>
            </section>
          )}
          {next ? (
            <section className="card next-task">
              <div className="task-kicker">
                <Route size={16} />
                YOUR NEXT INSPECTION
              </div>
              <div className="task-meta">
                <span>
                  {next.asset.zone} / {next.asset.id}
                </span>
                {next.progress.warnings[0] && (
                  <span>
                    <Clock3 size={14} />
                    Due {localTime(next.progress.warnings[0].dueAt)}
                  </span>
                )}
              </div>
              <h2>Inspect {next.asset.name}.</h2>
              <p className="task-reason">
                {next.progress.warnings[0]?.nextAction ??
                  `Record ${next.asset.metric.toLowerCase()} and check for changes at the equipment.`}
              </p>
              <div className="field-summary">
                <ShieldCheck size={17} />
                <p>{next.reason}</p>
              </div>
              <Link
                className={`button ${pending.length ? "secondary" : "primary"}`}
                href={`/inspect/${next.asset.id}`}
              >
                {next.progress.reading
                  ? "Continue inspection"
                  : "Start inspection"}{" "}
                <ArrowRight size={17} />
              </Link>
              <Link href={`/a/${next.asset.id}`} className="text-link">
                Equipment record <ArrowUpRight size={14} />
              </Link>
            </section>
          ) : (
            <section className="card next-task">
              <ShieldCheck />
              <h2>Your round is recorded.</h2>
              <p>
                Ongoing warnings remain active. Review your commitments before
                handing over.
              </p>
              <Link href="/handover" className="button primary">
                Prepare the handover <ArrowRight size={17} />
              </Link>
            </section>
          )}
          <div className="section-heading">
            <h2>Coming up on your round</h2>
            <Link href="/rounds">
              Full walking route <ArrowUpRight size={15} />
            </Link>
          </div>
          <div className="card task-queue">
            {tasks
              .filter((task) => !task.progress.completed && task !== next)
              .slice(0, 3)
              .map((task, i) => (
                <Link
                  className="task-stop"
                  key={task.asset.id}
                  href={`/inspect/${task.asset.id}`}
                >
                  <span className="task-number">
                    {String(i + 2).padStart(2, "0")}
                  </span>
                  <div className="task-stop-copy">
                    <strong>{task.asset.name}</strong>
                    <small>{task.reason}</small>
                  </div>
                  <ChevronRight size={17} />
                </Link>
              ))}
            {tasks.every((task) => task.progress.completed) && (
              <p className="caption">
                All planned stops have a recorded inspection.
              </p>
            )}
          </div>
        </div>
        <aside className="task-context">
          <div className="section-heading first">
            <h2>Commitments to carry forward</h2>
          </div>
          {open.length ? (
            open.map((warning) => (
              <Link
                className="card commitment"
                href={`/warnings/${warning.id}`}
                key={warning.id}
              >
                <span className={`badge ${warning.severity}`}>
                  {warning.state === "owned"
                    ? "Owned · follow-through pending"
                    : "Read-back needed"}
                </span>
                <h3>{warning.title}</h3>
                <p>{warning.nextAction}</p>
                <small>
                  {state.people.find((person) => person.id === warning.ownerId)
                    ?.name ?? warning.ownerId}{" "}
                  · Due {localTime(warning.dueAt)}
                </small>
                <span className="text-link">
                  Review commitment <ArrowRight size={14} />
                </span>
              </Link>
            ))
          ) : (
            <div className="card commitment">
              <ShieldCheck size={23} />
              <h3>No open commitments.</h3>
              <p>
                Record changes during your round so the next shift has the
                context.
              </p>
            </div>
          )}
          <div className="field-summary">
            <ShieldCheck size={18} />
            <p>
              Recording an inspection never clears an ongoing warning or
              operates equipment.
            </p>
          </div>
          <Link href="/tags" className="button secondary full">
            <MapPin size={17} />
            Open equipment tag wall
          </Link>
        </aside>
      </div>
    </div>
  );
}
export function WorkRounds({ state }: { state: PlantState }) {
  const tasks = roundTasks(state),
    next = tasks.find((task) => !task.progress.completed);
  return (
    <>
      <ShiftJourney state={state} current="rounds" />
      {next && (
        <section className="card next-task">
          <span className="task-kicker">NEXT STOP · {next.asset.id}</span>
          <h2>{next.asset.name}</h2>
          <p>{next.reason}</p>
          <Link href={`/inspect/${next.asset.id}`} className="button primary">
            {next.progress.reading ? "Continue inspection" : "Start inspection"}{" "}
            <ArrowRight size={17} />
          </Link>
        </section>
      )}
      <div className="section-heading">
        <h2>Your walking route</h2>
        <span className="micro">
          {tasks.filter((task) => task.progress.completed).length} /{" "}
          {tasks.length} INSPECTIONS RECORDED
        </span>
      </div>
      <div className="card work-list">
        {tasks.map((task, i) => (
          <Link
            href={`/inspect/${task.asset.id}`}
            className={`task-stop ${task.progress.completed ? "recorded" : ""}`}
            key={task.asset.id}
          >
            <span className="task-number">
              {task.progress.completed ? (
                <Check size={18} />
              ) : (
                String(i + 1).padStart(2, "0")
              )}
            </span>
            <div className="task-stop-copy">
              <strong>{task.asset.name}</strong>
              <small>{task.reason}</small>
            </div>
            <span className="task-stop-status">
              {task.progress.completed
                ? "Recorded"
                : task.progress.reading
                  ? "In progress"
                  : "Inspect"}
            </span>
            <ChevronRight size={16} />
          </Link>
        ))}
      </div>
      <p className="caption">
        Stops are ranked by drift, criticality, and field observations.
        Recording a stop preserves its open commitments.
      </p>
      <Link href="/handover" className="text-link">
        Prepare the shift handover <ArrowRight size={16} />
      </Link>
    </>
  );
}
export function StartShift({ state, open }: { state: PlantState; open: Open }) {
  const pending = state.handover.filter((item) => !item.confirmed);
  const receivedAt = state.audit.findIndex(
    (item) => item.action === "handover.received",
  );
  if (
    receivedAt >= 0 &&
    state.audit.some(
      (item, index) => index > receivedAt && item.action === "handover.drafted",
    )
  )
    return (
      <>
        <ShiftJourney state={state} current="start" />
        <section className="card next-task">
          <span className="task-kicker">INCOMING HANDOVER RECEIVED</span>
          <h2>You already have the shift context.</h2>
          <p>
            {state.audit[receivedAt].detail}. Preparing your outgoing brief
            preserves this receipt.
          </p>
          {state.audit
            .slice(0, receivedAt)
            .filter((item) => item.action === "handover.confirmed")
            .map((item) => (
              <blockquote key={item.id}>{item.detail}</blockquote>
            ))}
          <div className="inspection-actions">
            <Link href="/rounds" className="button primary">
              Continue my rounds <ArrowRight size={17} />
            </Link>
            <Link href="/handover" className="button secondary">
              Review my outgoing handover
            </Link>
          </div>
        </section>
      </>
    );
  return (
    <>
      <ShiftJourney state={state} current="start" />
      <section className="card next-task">
        <span className="task-kicker">RECEIVE THE SHIFT · MARIA SANTOS</span>
        <h2>
          {pending.length
            ? "Take the context with you."
            : "You have the handover."}
        </h2>
        <p>
          {pending.length
            ? "Read each inherited action and confirm what you will do. Your read-back stays with the item."
            : "Your read-backs are recorded. Start the highest-priority inspection when you reach the floor."}
        </p>
        {!pending.length && (
          <Link className="button primary" href="/rounds">
            Begin my rounds <ArrowRight size={17} />
          </Link>
        )}
      </section>
      <div className="handover-list intake-list">
        {state.handover.map((item, i) => (
          <article
            className={`card handover-item ${item.confirmed ? "confirmed" : ""}`}
            key={item.id}
          >
            <div className="handover-index">
              {item.confirmed ? (
                <Check size={24} />
              ) : (
                String(i + 1).padStart(2, "0")
              )}
            </div>
            <div className="grow">
              <div className="row-between">
                <Link href={`/a/${item.assetId}`} className="micro">
                  {item.assetId} <ArrowUpRight size={13} />
                </Link>
                <span className={`badge ${item.severity}`}>
                  {item.confirmed ? "Read-back recorded" : item.severity}
                </span>
              </div>
              <h2>{item.summary}</h2>
              <div className="ipass">
                <p>
                  <span>YOUR NEXT ACTION</span>
                  {item.action}
                </p>
                <p>
                  <span>IF THINGS CHANGE</span>
                  {item.contingency}
                </p>
              </div>
              {item.confirmed ? (
                <blockquote>“{item.readback}”</blockquote>
              ) : (
                <button
                  className="button primary"
                  onClick={() => open("confirm", item.id)}
                >
                  Confirm with a read-back <CheckCheck size={17} />
                </button>
              )}
            </div>
          </article>
        ))}
      </div>
      {!state.handover.length && (
        <div className="card next-task">
          <p>No incoming handover has been prepared for this seeded shift.</p>
          <Link href="/rounds" className="button primary">
            Begin my rounds <ArrowRight size={17} />
          </Link>
        </div>
      )}
      {pending.length > 0 && (
        <p className="caption">
          Urgent work remains accessible while you review:{" "}
          <Link href="/rounds">open the walking route</Link>.
        </p>
      )}
    </>
  );
}

export function GuidedInspection({
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
  const asset = state.assets.find((item) => item.id === assetId),
    progress = inspectionProgress(state, assetId);
  const [step, setStep] = useState(
      progress.completed
        ? 5
        : progress.reading
          ? progress.observation
            ? 3
            : 2
          : 0,
    ),
    [reading, setReading] = useState(asset ? String(asset.value) : ""),
    [observation, setObservation] = useState("");
  const reduced = useReducedMotion();
  useEffect(() => {
    document
      .querySelector('.inspection-step[aria-current="step"]')
      ?.scrollIntoView({
        block: "nearest",
        inline: "nearest",
        behavior: "auto",
      });
  }, [step]);
  if (!asset)
    return (
      <section className="card next-task">
        <h2>Equipment not found.</h2>
        <Link href="/rounds" className="button primary">
          Return to my rounds
        </Link>
      </section>
    );
  const notes = state.notes.filter((item) => item.assetId === asset.id),
    unowned = progress.warnings.filter((item) => item.state !== "owned"),
    steps = [
      "Review evidence",
      "Record reading",
      "Add observation",
      "Confirm ownership",
      "Record inspection",
    ];
  const noteSaved = async (text: string) => {
    if (
      await send(
        { type: "note", assetId, text },
        "Observation saved to the equipment record",
      )
    )
      setStep(3);
  };
  const next = roundTasks(state).find(
    (task) => task.asset.id !== assetId && !task.progress.completed,
  );
  const ready = progress.reading && progress.observation && progress.owned;
  return (
    <>
      <ShiftJourney state={state} current="rounds" />
      <div className="inspection-layout">
        <div>
          <nav className="inspection-steps" aria-label="Inspection steps">
            {steps.map((label, i) => (
              <button
                key={label}
                className={`inspection-step ${step === i ? "current" : ""} ${step > i ? "complete" : ""}`}
                disabled={busy || i > step}
                onClick={() => setStep(i)}
                aria-current={step === i ? "step" : undefined}
              >
                <span>{step > i ? <Check size={14} /> : i + 1}</span>
                {label}
              </button>
            ))}
          </nav>
          <section className="card inspection-panel">
            <AnimatePresence mode="wait">
              <motion.div
                className="inspection-stage"
                key={step}
                initial={{
                  opacity: 0,
                  transform: reduced ? "none" : "translateY(6px)",
                }}
                animate={{ opacity: 1, transform: "translateY(0px)" }}
                exit={{ opacity: 0 }}
                transition={{
                  duration: reduced ? 0.01 : 0.16,
                  ease: [0.23, 1, 0.32, 1],
                }}
              >
                {step === 0 && (
                  <>
                    <span className="task-kicker">
                      STEP 1 / 5 · AT THE EQUIPMENT
                    </span>
                    <h2>Know why you’re here.</h2>
                    <p>
                      {progress.warnings[0]?.nextAction ??
                        `Check ${asset.metric.toLowerCase()} and record anything that changed.`}
                    </p>
                    <dl className="inspection-facts">
                      <div>
                        <dt>Equipment</dt>
                        <dd>
                          {asset.name} · {asset.id}
                        </dd>
                      </div>
                      <div>
                        <dt>Location</dt>
                        <dd>{asset.zone}</dd>
                      </div>
                      <div>
                        <dt>Latest telemetry</dt>
                        <dd>
                          {asset.value.toFixed(1)} {asset.unit}
                        </dd>
                      </div>
                      <div>
                        <dt>Baseline</dt>
                        <dd>
                          {asset.baseline.toFixed(1)} {asset.unit}
                        </dd>
                      </div>
                    </dl>
                    {notes.map((note) => (
                      <article className="inspection-note" key={note.id}>
                        <span className="micro">
                          PINNED OBSERVATION · {note.author}
                        </span>
                        <p>{note.text}</p>
                      </article>
                    ))}
                    {progress.warnings.map((warning) => (
                      <div className="field-summary" key={warning.id}>
                        <TriangleAlert size={18} />
                        <p>{warning.evidence[0] ?? warning.title}</p>
                      </div>
                    ))}
                    <div className="inspection-actions">
                      <button
                        className="button primary"
                        onClick={() => setStep(1)}
                      >
                        Evidence reviewed · take a reading{" "}
                        <ArrowRight size={17} />
                      </button>
                    </div>
                  </>
                )}
                {step === 1 && (
                  <>
                    <span className="task-kicker">
                      STEP 2 / 5 · {asset.metric.toUpperCase()}
                    </span>
                    <h2>What does the equipment read?</h2>
                    <p>
                      Enter the value you observe at the equipment. Telemetry is
                      shown for comparison.
                    </p>
                    <form
                      className="inspection-form"
                      onSubmit={async (event) => {
                        event.preventDefault();
                        if (
                          reading.trim() &&
                          Number.isFinite(Number(reading)) &&
                          (await send(
                            {
                              type: "reading",
                              assetId,
                              value: Number(reading),
                            },
                            "Reading recorded and checked against the baseline",
                          ))
                        )
                          setStep(2);
                      }}
                    >
                      <label>
                        Observed reading
                        <div className="reading-input">
                          <input
                            aria-label="Inspection reading"
                            inputMode="decimal"
                            value={reading}
                            onChange={(event) => setReading(event.target.value)}
                          />
                          <span>{asset.unit}</span>
                        </div>
                      </label>
                      <div className="field-summary">
                        <Route size={18} />
                        <p>
                          Baseline {asset.baseline.toFixed(1)} {asset.unit}
                          {reading.trim() && Number.isFinite(Number(reading))
                            ? ` · Difference ${(Number(reading) - asset.baseline).toFixed(1)} ${asset.unit}`
                            : ""}
                        </p>
                      </div>
                      <button
                        type="submit"
                        className="button primary"
                        disabled={
                          busy ||
                          !reading.trim() ||
                          !Number.isFinite(Number(reading))
                        }
                      >
                        {busy ? "Saving reading…" : "Save reading and continue"}{" "}
                        <ArrowRight size={17} />
                      </button>
                    </form>
                  </>
                )}
                {step === 2 && (
                  <>
                    <span className="task-kicker">
                      STEP 3 / 5 · FIELD OBSERVATION
                    </span>
                    <h2>What changed on the floor?</h2>
                    <p>
                      Capture what a sensor cannot: sound, vibration, heat,
                      leaks, or the condition you inspected.
                    </p>
                    <form
                      className="inspection-form"
                      onSubmit={(event) => {
                        event.preventDefault();
                        void noteSaved(observation);
                      }}
                    >
                      <label htmlFor="inspection-observation">
                        Your observation
                      </label>
                      <textarea
                        id="inspection-observation"
                        aria-label="Inspection observation"
                        value={observation}
                        onChange={(event) => setObservation(event.target.value)}
                        rows={5}
                        placeholder="Describe what you found at the equipment…"
                      />
                      <div className="inspection-actions">
                        <button
                          type="submit"
                          className="button primary"
                          disabled={busy || !observation.trim()}
                        >
                          Save observation <ArrowRight size={17} />
                        </button>
                        <button
                          type="button"
                          className="button secondary"
                          disabled={busy}
                          onClick={() =>
                            void noteSaved(
                              `Inspection observation: no new findings at ${asset.name}.`,
                            )
                          }
                        >
                          Record no new findings
                        </button>
                      </div>
                    </form>
                  </>
                )}
                {step === 3 && (
                  <>
                    <span className="task-kicker">
                      STEP 4 / 5 · CLOSE THE OWNERSHIP LOOP
                    </span>
                    <h2>
                      {unowned.length
                        ? "Give the next action an owner."
                        : "The next action has an owner."}
                    </h2>
                    {unowned[0] ? (
                      <>
                        <p>{unowned[0].title}</p>
                        <div className="field-summary">
                          <Clock3 size={18} />
                          <p>
                            {unowned[0].nextAction} · Due{" "}
                            {localTime(unowned[0].dueAt)} · Owner:{" "}
                            {state.people.find(
                              (person) => person.id === unowned[0].ownerId,
                            )?.name ?? unowned[0].ownerId}
                          </p>
                        </div>
                        <button
                          className="button primary"
                          disabled={busy}
                          onClick={() =>
                            void send(
                              {
                                type: "take_ownership",
                                warningId: unowned[0].id,
                              },
                              "Follow-up accepted",
                            )
                          }
                        >
                          Take this follow-up <Check size={17} />
                        </button>
                      </>
                    ) : (
                      <>
                        {progress.warnings.length ? (
                          progress.warnings.map((warning) => (
                            <blockquote key={warning.id}>
                              {warning.readback || "Follow-up accepted"}
                              <small>
                                {state.people.find(
                                  (person) => person.id === warning.ownerId,
                                )?.name ?? warning.ownerId}{" "}
                                · Warning remains active
                              </small>
                            </blockquote>
                          ))
                        ) : (
                          <p>
                            No open warning requires an owner for this
                            equipment.
                          </p>
                        )}
                        <div className="inspection-actions">
                          <button
                            className="button primary"
                            onClick={() => setStep(4)}
                          >
                            Review the inspection record{" "}
                            <ArrowRight size={17} />
                          </button>
                        </div>
                      </>
                    )}
                  </>
                )}
                {step === 4 && (
                  <>
                    <span className="task-kicker">
                      STEP 5 / 5 · REVIEW BEFORE RECORDING
                    </span>
                    <h2>Keep the work and its commitments together.</h2>
                    <div className="inspection-receipt">
                      <p>
                        <Check size={17} />
                        {progress.readingAudit?.detail ??
                          "A fresh reading is still required."}
                      </p>
                      <p>
                        <Check size={17} />
                        {progress.observation
                          ? "An observation is attached to the equipment."
                          : "An observation after this reading is still required."}
                      </p>
                      <p>
                        <CheckCheck size={17} />
                        {progress.owned
                          ? "Every active warning has an accepted owner."
                          : "Confirm ownership for each active warning."}
                      </p>
                    </div>
                    <p>
                      Recording this inspection saves your visit. Ongoing
                      warnings and follow-up work remain active for the team and
                      the next shift.
                    </p>
                    <div className="inspection-actions">
                      <button
                        className="button primary"
                        disabled={busy || !ready}
                        onClick={async () => {
                          if (
                            await send(
                              { type: "complete_inspection", assetId },
                              "Inspection recorded; ongoing commitments remain active",
                            )
                          )
                            setStep(5);
                        }}
                      >
                        Record inspection <Check size={17} />
                      </button>
                    </div>
                    {!ready && (
                      <Link
                        className="text-link"
                        href={`/inspect/${assetId}`}
                        onClick={() =>
                          setStep(
                            !progress.reading
                              ? 1
                              : !progress.observation
                                ? 2
                                : 3,
                          )
                        }
                      >
                        Return to the missing step <ArrowRight size={15} />
                      </Link>
                    )}
                  </>
                )}
                {step === 5 && (
                  <div className="inspection-result">
                    <ShieldCheck size={38} />
                    <span className="task-kicker">RECORDED IN THIS SHIFT</span>
                    <h2>{asset.name} inspection recorded.</h2>
                    <p>
                      Your reading, observation, and ownership record stay with
                      the equipment.{" "}
                      {progress.warnings.length
                        ? "Its ongoing warnings remain active."
                        : "The next technician can review what you found."}
                    </p>
                    <div className="inspection-actions">
                      {next ? (
                        <Link
                          className="button primary"
                          href={`/inspect/${next.asset.id}`}
                        >
                          Next stop: {next.asset.name} <ArrowRight size={17} />
                        </Link>
                      ) : (
                        <Link href="/handover" className="button primary">
                          Prepare my handover <ArrowRight size={17} />
                        </Link>
                      )}
                      <Link href="/rounds" className="button secondary">
                        Back to my round
                      </Link>
                    </div>
                  </div>
                )}
              </motion.div>
            </AnimatePresence>
          </section>
        </div>
        <aside className="task-context">
          <section className="card commitment">
            <span className="task-kicker">EQUIPMENT CONTEXT</span>
            <h3>{asset.name}</h3>
            <p>
              {asset.zone} · {asset.id}
            </p>
            <Link className="text-link" href={`/a/${asset.id}`}>
              Full equipment record <ArrowUpRight size={15} />
            </Link>
          </section>
          {progress.warnings.map((warning) => (
            <Link
              href={`/warnings/${warning.id}`}
              className="card commitment"
              key={warning.id}
            >
              <span className={`badge ${warning.severity}`}>
                {warning.state === "owned"
                  ? "Owned · ongoing"
                  : warning.severity}
              </span>
              <h3>{warning.title}</h3>
              <p>{warning.nextAction}</p>
              <small>Due {localTime(warning.dueAt)}</small>
            </Link>
          ))}
          <Link
            className="button secondary full"
            href={`/procedures?asset=${asset.id}`}
          >
            <BookOpen size={17} />
            Open a procedure
          </Link>
          <div className="field-summary">
            <ShieldAlert size={18} />
            <p>
              This inspection records observations. Maintenance actions still
              require an approved procedure and a live GO/HOLD check.
            </p>
          </div>
        </aside>
      </div>
    </>
  );
}
export function PresenterHome() {
  return (
    <section className="card next-task presenter-home">
      <span className="task-kicker">PRESENTER WORKSPACE</span>
      <h2>Set the scene. Then follow the technician.</h2>
      <p>
        Scenario controls and agent traces are kept here, outside the floor
        workflow.
      </p>
      <div className="presenter-links">
        <Link className="button primary" href="/_director">
          <Layers3 size={18} />
          Scenario Director <ArrowRight size={16} />
        </Link>
        <Link className="button secondary" href="/traces">
          <Route size={18} />
          Agent decision traces
        </Link>
        <Link className="button secondary" href="/phone">
          <MessageCircle size={18} />
          Message mirror
        </Link>
        <Link className="button secondary" href="/tags">
          <MapPin size={18} />
          Equipment tags
        </Link>
      </div>
      <Link className="text-link" href="/">
        Return to the field experience <ArrowRight size={16} />
      </Link>
    </section>
  );
}
