"use client";

import { useState } from "react";
import Link from "next/link";
import {
  ArrowRight,
  ArrowUpRight,
  CalendarClock,
  Check,
  CheckCheck,
  ChevronRight,
  ClipboardList,
  Clock3,
  FileCheck2,
  GitBranch,
  LockKeyhole,
  MapPin,
  ShieldCheck,
  TriangleAlert,
} from "lucide-react";
import type {
  FleetCommand,
  FleetState,
  FleetTicket,
  Technician,
  MaintenancePlan,
} from "../../../packages/contracts/fleet";

import {
  rankTechnicianQueue,
  shiftBriefSignature,
} from "../../../packages/contracts/work-order";

type Send = (command: FleetCommand) => Promise<boolean>;
type Props = { state: FleetState; me: Technician; send: Send; busy: boolean };
const human = (value: string) => value.replaceAll("_", " ");
const time = (value: string) =>
  new Date(value).toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
    timeZone: "America/Chicago",
  });
const label = (id: string) =>
  `FW-${id.replaceAll("-", "").slice(-6).toUpperCase()}`;
const completed = (ticket: FleetTicket) =>
  ticket.steps.filter((step) => step.completed);

export const nextWorkQueue = rankTechnicianQueue;

export function NextWork({ state, me }: Pick<Props, "state" | "me">) {
  const queue = nextWorkQueue(state, me.id),
    next = queue[0];
  const needsHandover =
    next?.priority === "critical" &&
    !["accepted", "in_progress"].includes(next.status) &&
    queue.some(
      (ticket) =>
        ticket.id !== next.id &&
        ["accepted", "in_progress"].includes(ticket.status),
    );
  const explanation = needsHandover
    ? "Coordinate a safe handover of your active job before taking this response."
    : next?.priority === "critical"
      ? "Urgent response takes precedence over planned work."
      : next && ["accepted", "in_progress"].includes(next.status)
        ? "Continue the work you already accepted before starting another job."
        : next?.dueAt
          ? "The earliest due assignment comes next."
          : "Your next qualified assignment is ready for review.";
  return (
    <section className="op-next">
      <div className="op-next-heading">
        <span className="op-icon">
          <ClipboardList size={20} />
        </span>
        <div>
          <h2>
            {needsHandover
              ? "Urgent response: coordinate a safe handover"
              : next
                ? "Your next action"
                : "Your queue is clear"}
          </h2>
          <p>
            {next
              ? explanation
              : "Upcoming upkeep and unassigned coverage remain visible in the shift brief."}
          </p>
        </div>
        <Link className="op-text-link" href="/brief">
          Shift brief
          <ArrowUpRight size={14} />
        </Link>
      </div>
      {next && (
        <div className="op-next-job">
          <div>
            <span className="op-meta">
              {label(next.id)} · Sector {next.sectorId}
              {next.dueAt ? ` · Due ${time(next.dueAt)}` : ""}
            </span>
            <h3>{next.title}</h3>
            <p>
              {completed(next).length
                ? `${completed(next).length} checks completed. ${next.steps.find((step) => !step.completed)?.label ?? "All checks recorded; review and close the job."}`
                : next.summary}
            </p>
          </div>
          <Link className="fl-button fl-primary" href={`/tickets/${next.id}`}>
            {["accepted", "in_progress"].includes(next.status)
              ? "Continue work"
              : "Review assignment"}
            <ArrowRight size={15} />
          </Link>
        </div>
      )}
    </section>
  );
}

export function ShiftBrief({
  state,
  me,
  send,
  busy,
  compact = false,
}: Props & { compact?: boolean }) {
  const open = state.tickets.filter((ticket) => ticket.status !== "resolved");
  const urgent = open.filter(
    (ticket) => ticket.priority === "critical" || ticket.status === "escalated",
  );
  const accepted = open.filter((ticket) =>
    ["accepted", "in_progress"].includes(ticket.status),
  );
  const blocked = (state.maintenancePlans ?? []).filter((plan) =>
    plan.blockers.some((blocker) => !blocker.clearedAt),
  );
  const gaps = state.sectors.filter(
    (sector) =>
      !state.technicians.some(
        (technician) =>
          technician.available &&
          technician.subscriptions.includes(sector.id) &&
          technician.clearances.includes(sector.id),
      ),
  );
  const review = (state.shiftReviews ?? [])
    .filter((item) => item.technicianId === me.id)
    .at(-1);
  const [reviewing, setReviewing] = useState(false);
  async function markReviewed() {
    setReviewing(true);
    try {
      await send({ type: "shift_review", technicianId: me.id });
    } finally {
      setReviewing(false);
    }
  }
  const changed = !!review && review.signature !== shiftBriefSignature(state);
  if (compact)
    return (
      <section className="op-compact-brief">
        <strong>Shift continuity</strong>
        <span>
          <b>{urgent.length}</b> urgent
        </span>
        <span>
          <b>{accepted.length}</b> in progress
        </span>
        <span>
          <b>{blocked.length}</b> blocked plans
        </span>
        <Link href="/brief">
          Open shift brief
          <ArrowRight size={13} />
        </Link>
      </section>
    );
  return (
    <div className="op-brief">
      <section className="op-brief-header">
        <div>
          <h2>What needs attention</h2>
          <p>
            Urgent carryover, work already in progress, and prerequisites that
            still need attention.
          </p>
        </div>
        <div>
          <button
            className="fl-button fl-primary"
            disabled={busy || reviewing}
            onClick={() => void markReviewed()}
          >
            <FileCheck2 size={16} />
            {reviewing ? "Recording review…" : "Mark this brief reviewed"}
          </button>
          {review && (
            <span className="op-reviewed">
              <CheckCheck size={12} />
              {changed
                ? "Work or coverage changed since review"
                : `Reviewed ${time(review.reviewedAt)}`}
            </span>
          )}
        </div>
      </section>
      <div className="op-review-scope">
        <ShieldCheck size={14} />
        Review records what you saw. Job assignments and responsibilities stay
        with their current owners.
      </div>
      <div className="op-brief-grid">
        <section className="op-section">
          <div className="op-section-title">
            <h3>
              <TriangleAlert size={17} />
              Urgent carryover
            </h3>
            <span>{urgent.length}</span>
          </div>
          {urgent.length ? (
            urgent.map((ticket) => (
              <BriefJob key={ticket.id} ticket={ticket} state={state} />
            ))
          ) : (
            <Quiet text="No urgent or escalated work is waiting." />
          )}
        </section>
        <section className="op-section">
          <div className="op-section-title">
            <h3>
              <GitBranch size={17} />
              Work in progress
            </h3>
            <span>{accepted.length}</span>
          </div>
          {accepted.length ? (
            accepted.map((ticket) => (
              <BriefJob
                key={ticket.id}
                ticket={ticket}
                state={state}
                progress
              />
            ))
          ) : (
            <Quiet text="No accepted jobs are carrying over." />
          )}
        </section>
      </div>
      <div className="op-brief-grid">
        <section className="op-section">
          <div className="op-section-title">
            <h3>
              <LockKeyhole size={17} />
              Blocked upcoming work
            </h3>
            <span>{blocked.length}</span>
          </div>
          {blocked.length ? (
            blocked.map((plan) => (
              <article className="op-blocked-summary" key={plan.id}>
                <Link href="/upkeep">
                  <strong>{plan.title}</strong>
                  <ArrowUpRight size={14} />
                </Link>
                <p>
                  Sector {plan.sectorId} · {plan.assetId} · Due{" "}
                  {time(plan.dueAt)}
                </p>
                {plan.blockers
                  .filter((blocker) => !blocker.clearedAt)
                  .map((blocker) => (
                    <span key={blocker.id}>
                      <LockKeyhole size={12} />
                      {blocker.label}
                    </span>
                  ))}
              </article>
            ))
          ) : (
            <Quiet text="No outstanding prerequisites block planned work." />
          )}
        </section>
        <section className="op-section">
          <div className="op-section-title">
            <h3>
              <MapPin size={17} />
              Sector coverage
            </h3>
            <Link href="/team">
              Manage
              <ArrowUpRight size={12} />
            </Link>
          </div>
          {state.sectors.map((sector) => {
            const subscribers = state.technicians.filter(
              (technician) =>
                technician.available &&
                technician.subscriptions.includes(sector.id) &&
                technician.clearances.includes(sector.id),
            );
            return (
              <div className="op-coverage" key={sector.id}>
                <span className="op-sector-letter">{sector.id}</span>
                <div>
                  <strong>{sector.name}</strong>
                  <p>
                    {subscribers.length
                      ? subscribers
                          .map((technician) => technician.name)
                          .join(", ")
                      : "No available subscriber with sector access"}
                  </p>
                </div>
                <span
                  className={`op-status ${subscribers.length ? "" : "attention"}`}
                >
                  {subscribers.length ? "Covered" : "Gap"}
                </span>
              </div>
            );
          })}
          {gaps.length > 0 && (
            <p className="op-coverage-note">
              Uncovered work must escalate to an eligible on-call responder.
              Skills and equipment are still checked for each assignment.
            </p>
          )}
        </section>
      </div>
      {review && (
        <details className="op-review-record">
          <summary>
            Last reviewed snapshot
            <ChevronRight size={14} />
          </summary>
          <p>
            {review.openTicketIds.length} open jobs and{" "}
            {review.blockedPlanIds.length} blocked plans were recorded at{" "}
            {time(review.reviewedAt)}. This page continues to show current
            state.
          </p>
          <div>
            {review.openTicketIds.map((id) => (
              <Link href={`/tickets/${id}`} key={id}>
                {label(id)}
                <ArrowUpRight size={11} />
              </Link>
            ))}
          </div>
        </details>
      )}
    </div>
  );
}

function BriefJob({
  ticket,
  state,
  progress = false,
}: {
  ticket: FleetTicket;
  state: FleetState;
  progress?: boolean;
}) {
  const owner = state.technicians.find(
      (technician) => technician.id === ticket.assigneeId,
    ),
    done = completed(ticket),
    remaining = ticket.steps.filter((step) => !step.completed);
  return (
    <article className="op-brief-job">
      <div className="op-job-meta">
        <span>
          {label(ticket.id)} · Sector {ticket.sectorId}
        </span>
        <span className="op-status">{human(ticket.status)}</span>
      </div>
      <Link className="op-job-title" href={`/tickets/${ticket.id}`}>
        {ticket.title}
        <ArrowUpRight size={14} />
      </Link>
      <p>
        {owner?.name ?? "Awaiting eligible responder"} · {done.length}/
        {ticket.steps.length} checks recorded
      </p>
      {progress && remaining[0] && (
        <div className="op-pickup">
          <ArrowRight size={13} />
          <span>Next: {remaining[0].label}</span>
        </div>
      )}
      <details>
        <summary>
          Completed work & handoff
          <ChevronRight size={13} />
        </summary>
        <div className="op-brief-evidence">
          {ticket.handoff.summary && <p>{ticket.handoff.summary}</p>}
          <h4>Already completed</h4>
          {done.length ? (
            done.map((step) => (
              <p key={step.id}>
                <Check size={12} />
                <span>
                  {step.label}
                  {step.note && <small>{step.note}</small>}
                </span>
              </p>
            ))
          ) : (
            <p>No physical checks recorded.</p>
          )}
          <h4>Remaining</h4>
          {remaining.length ? (
            remaining.map((step) => (
              <p key={step.id}>
                <ArrowRight size={12} />
                <span>{step.label}</span>
              </p>
            ))
          ) : (
            <p>All checks recorded. Review before closure.</p>
          )}
        </div>
      </details>
    </article>
  );
}

export function Upkeep({ state, me, send, busy }: Props) {
  const plans = state.maintenancePlans ?? [],
    [filter, setFilter] = useState("all");
  const visible = plans.filter(
    (plan) =>
      filter === "all" ||
      (filter === "blocked"
        ? plan.blockers.some((blocker) => !blocker.clearedAt)
        : plan.ticketId && plan.status !== "complete"),
  );
  return (
    <div className="op-upkeep">
      <section className="op-upkeep-header">
        <div>
          <h2>Prepare the work before it is due.</h2>
          <p>
            Review maintenance windows, clear documented prerequisites, and
            dispatch ready work with its context attached.
          </p>
        </div>
        <button
          className="fl-button fl-primary"
          disabled={
            busy || plans.some((plan) => plan.status === "investigating")
          }
          onClick={() => void send({ type: "review_upkeep" })}
        >
          <CalendarClock size={16} />
          {plans.some((plan) => plan.status === "investigating")
            ? "Review in progress…"
            : "Review upcoming work"}
        </button>
      </section>
      <div className="fl-tabbar">
        {[
          ["all", "All plans"],
          ["blocked", "Blocked"],
          ["linked", "Dispatched"],
        ].map(([id, name]) => (
          <button
            key={id}
            className={id === filter ? "active" : ""}
            onClick={() => setFilter(id)}
          >
            {name}
          </button>
        ))}
      </div>
      <div className="op-plans">
        {visible.map((plan) => (
          <Plan
            key={plan.id}
            plan={plan}
            state={state}
            me={me}
            send={send}
            busy={busy}
          />
        ))}
        {!visible.length && (
          <Quiet text="No plans in this view. Choose another filter or start the upkeep scenario." />
        )}
      </div>
    </div>
  );
}

function Plan({
  plan,
  state,
  me,
  send,
  busy,
}: Props & { plan: MaintenancePlan }) {
  const [notes, setNotes] = useState<Record<string, string>>({});
  const blocked = plan.blockers.filter((blocker) => !blocker.clearedAt),
    linked = state.tickets.find((ticket) => ticket.id === plan.ticketId);
  const isSenior = me.level === "senior",
    due = new Date(plan.dueAt).getTime() <= new Date(state.clock).getTime();
  return (
    <article className="op-plan">
      <div className="op-plan-top">
        <span className="op-icon">
          {plan.kind === "retirement_readiness" ? (
            <GitBranch size={21} />
          ) : (
            <CalendarClock size={21} />
          )}
        </span>
        <div>
          <h3>{plan.title}</h3>
          <p>
            Sector {plan.sectorId} · {plan.assetId} ·{" "}
            {plan.kind === "retirement_readiness"
              ? "Retirement readiness"
              : "Preventive inspection"}
          </p>
        </div>
        <span className={`op-status ${blocked.length ? "attention" : ""}`}>
          {human(plan.status)}
        </span>
      </div>
      <div className="op-plan-timing">
        <span>
          <Clock3 size={14} />
          {due ? "Due" : "Due at"} {time(plan.dueAt)}
        </span>
        <span>
          Window {time(plan.windowStart)}–{time(plan.windowEnd)}
        </span>
        <span>{human(plan.requiredSkill)}</span>
      </div>
      {blocked.length > 0 && (
        <div className="op-plan-blocked">
          <LockKeyhole size={15} />
          <span>
            {blocked.length}{" "}
            {blocked.length === 1 ? "prerequisite needs" : "prerequisites need"}{" "}
            evidence before dispatch.
          </span>
        </div>
      )}
      {plan.blockers.length > 0 && (
        <details className="op-prerequisites" open={blocked.length > 0}>
          <summary>
            Prerequisites
            <span>
              {plan.blockers.length - blocked.length}/{plan.blockers.length}{" "}
              documented
            </span>
          </summary>
          {plan.blockers.map((blocker) => (
            <section key={blocker.id}>
              <div>
                <span className="op-check">
                  {blocker.clearedAt ? (
                    <Check size={14} />
                  ) : (
                    <LockKeyhole size={13} />
                  )}
                </span>
                <h4>{blocker.label}</h4>
              </div>
              {blocker.clearedAt ? (
                <div className="op-clearance">
                  <p>{blocker.note}</p>
                  <span>
                    {state.technicians.find(
                      (technician) => technician.id === blocker.clearedBy,
                    )?.name ?? blocker.clearedBy}{" "}
                    · {time(blocker.clearedAt)}
                  </span>
                </div>
              ) : isSenior ? (
                <form
                  onSubmit={async (event) => {
                    event.preventDefault();
                    if (
                      await send({
                        type: "plan_clearance",
                        planId: plan.id,
                        blockerId: blocker.id,
                        technicianId: me.id,
                        note: notes[blocker.id] ?? "",
                      })
                    )
                      setNotes({ ...notes, [blocker.id]: "" });
                  }}
                >
                  <label htmlFor={`evidence-${plan.id}-${blocker.id}`}>
                    Record verified evidence
                  </label>
                  <textarea
                    id={`evidence-${plan.id}-${blocker.id}`}
                    rows={2}
                    maxLength={1500}
                    value={notes[blocker.id] ?? ""}
                    onChange={(event) =>
                      setNotes({ ...notes, [blocker.id]: event.target.value })
                    }
                    placeholder="What was verified, by whom, and where is it documented?"
                    required
                  />
                  <button
                    className="fl-button fl-secondary"
                    disabled={
                      busy || (notes[blocker.id] ?? "").trim().length < 10
                    }
                  >
                    Record prerequisite evidence
                    <Check size={14} />
                  </button>
                </form>
              ) : (
                <p className="op-senior-only">
                  A senior technician must document verified evidence. Switch
                  “View as” to the senior responder in this demo.
                </p>
              )}
            </section>
          ))}
        </details>
      )}
      <details className="op-plan-detail">
        <summary>
          Scope & preparation
          <ChevronRight size={14} />
        </summary>
        <div>
          <h4>Required equipment</h4>
          <p>{plan.requiredEquipment.join(", ") || "Standard kit"}</p>
          <h4>Work scope</h4>
          {plan.steps.map((step, index) => (
            <p key={index}>
              <span>{index + 1}.</span>
              {step}
            </p>
          ))}
          {plan.lastEvaluation && (
            <>
              <h4>Latest review</h4>
              <p>
                {typeof plan.lastEvaluation === "string"
                  ? plan.lastEvaluation
                  : JSON.stringify(plan.lastEvaluation)}
              </p>
            </>
          )}
        </div>
      </details>
      {linked && linked.maintenancePlanId !== plan.id && (
        <p className="op-plan-foot">
          An existing visit covers this asset. This inspection remains pending;
          completing that visit does not complete the plan.
        </p>
      )}
      {plan.status === "blocked" && !blocked.length && (
        <p className="op-plan-foot">{plan.lastEvaluation}</p>
      )}
      {linked ? (
        <Link className="op-linked-ticket" href={`/tickets/${linked.id}`}>
          <ClipboardList size={17} />
          <span>
            <strong>
              {label(linked.id)} · {linked.title}
            </strong>
            <small>
              {state.technicians.find(
                (technician) => technician.id === linked.assigneeId,
              )?.name ?? "Awaiting responder"}{" "}
              · {human(linked.status)}
            </small>
          </span>
          <ArrowRight size={16} />
        </Link>
      ) : plan.status === "complete" ? (
        <div className="op-plan-complete">
          <CheckCheck size={16} />
          Recorded work complete
        </div>
      ) : (
        <p className="op-plan-foot">
          {blocked.length
            ? "Dispatch stays blocked until evidence is recorded and the plan is reviewed."
            : plan.status === "investigating"
              ? "An agent is reviewing readiness and preparing the field work."
              : "A readiness review determines whether this plan can be dispatched in its window."}
        </p>
      )}
    </article>
  );
}

function Quiet({ text }: { text: string }) {
  return (
    <div className="op-quiet">
      <ShieldCheck size={21} />
      <p>{text}</p>
    </div>
  );
}
