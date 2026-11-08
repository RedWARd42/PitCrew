"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { InvestigationLauncher } from "./investigation";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import {
  ArrowRight,
  ArrowUpRight,
  Activity,
  CheckCheck,
  CircleDot,
  FlaskConical,
  GitBranch,
  ShieldCheck,
  TriangleAlert,
  Zap,
  Pause,
  Play,
} from "lucide-react";
import type { PlantState } from "../../../packages/contracts";
import type {
  DecisionBrief,
  Rehearsal,
} from "../../../services/core/decisions";

export default function DecisionRoom({ state }: { state: PlantState }) {
  const reduced = useReducedMotion();
  const [orbitPaused, setOrbitPaused] = useState(false);
  const [brief, setBrief] = useState<DecisionBrief | null>(null);
  const [selected, setSelected] = useState("");
  const [tab, setTab] = useState<"evidence" | "rehearsal">("evidence");
  const [target, setTarget] = useState("PDU-4");
  const [result, setResult] = useState<Rehearsal | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    fetch("/api/decisions", { signal: controller.signal })
      .then(async (r) => {
        if (!r.ok) throw Error("Could not load the decision brief.");
        setBrief(await r.json());
        setError("");
      })
      .catch((e) => {
        if (e.name !== "AbortError") setError(e.message);
      });
    return () => controller.abort();
  }, [state, retry]);
  const topologyRevision = JSON.stringify([
    state.clock,
    state.assets.map((a) => [a.id, a.status, a.feeds]),
  ]);
  useEffect(() => setResult(null), [topologyRevision]);
  const focus =
    brief?.priorities.find((w) => w.id === selected) ?? brief?.priorities[0];
  const asset = state.assets.find((a) => a.id === focus?.assetId);
  async function simulate() {
    setBusy(true);
    setError("");
    setResult(null);
    try {
      const r = await fetch("/api/decisions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type: "open_breaker", target }),
      });
      const data = await r.json();
      if (!r.ok) throw Error(data.error);
      setResult(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Rehearsal unavailable");
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="decision-room">
      <div className="dr-intro">
        <Link href="/presenter">
          Demo scenarios <ArrowUpRight size={14} />
        </Link>
      </div>
      <section className="dr-hero">
        <div>
          <h2>Ahead of the incident.</h2>
          <Link href="/shift" className="button primary">
            Continue my shift <ArrowRight size={16} />
          </Link>
        </div>
        <div className="dr-orbit" aria-hidden="true" data-paused={orbitPaused}>
          <div className="dr-orbit-ring" />
          <div className="dr-orbit-ring inner" />
          <div className="dr-orbit-core">
            <ShieldCheck size={40} />
          </div>
          {[0, 1, 2].map((index) => (
            <div key={index} className={`dr-orbit-track track-${index}`}>
              <i />
            </div>
          ))}
        </div>
        <button
          className="dr-orbit-toggle"
          aria-label={
            orbitPaused ? "Resume orbit animation" : "Pause orbit animation"
          }
          onClick={() => setOrbitPaused(!orbitPaused)}
        >
          {orbitPaused ? <Play size={13} /> : <Pause size={13} />}
        </button>
      </section>
      {error && (
        <div className="alert" role="alert">
          {error}
          <button onClick={() => setRetry((n) => n + 1)}>Retry</button>
        </div>
      )}
      {state.incidents.map((incident) => (
        <Link key={incident.id} href="/incident" className="incident-banner">
          <TriangleAlert />
          <div>
            <strong>{incident.title}</strong>
            <p>
              {incident.alarmCount} correlated alarms ·{" "}
              {incident.etaMinutes === null
                ? "Time to limit not established"
                : `Estimated ${Math.round(incident.etaMinutes)} minutes to limit`}{" "}
              · Open incident response
            </p>
          </div>
          <ArrowRight />
        </Link>
      ))}
      <div className="dr-metrics">
        {[
          ["Open commitments", brief?.priorities.length],
          ["Awaiting owner", brief?.unaccepted],
          ["Past deadline", brief?.overdue],
          ["Handover items", brief?.handoverPending],
        ].map(([label, value]) => (
          <div key={label}>
            <span>{label}</span>
            <strong>{value ?? "—"}</strong>
          </div>
        ))}
      </div>
      <InvestigationLauncher state={state} />
      <div className="dr-section-title">
        <h2>Active work</h2>
      </div>
      <div className="dr-workbench">
        <aside className="dr-queue">
          <div className="dr-panel-heading">
            <Activity size={16} />
            <strong>Priority queue</strong>
            <span>{brief?.priorities.length ?? "—"}</span>
          </div>
          {!brief ? (
            <p className="dr-empty">Building your brief…</p>
          ) : !brief.priorities.length ? (
            <div className="dr-empty">
              <ShieldCheck />
              <h3>No open warnings.</h3>
              <p>
                Rehearse a maintenance action, or load “The quiet warning” in
                Demo scenarios.
              </p>
              <button
                className="button secondary"
                onClick={() => setTab("rehearsal")}
              >
                Rehearse maintenance
              </button>
            </div>
          ) : (
            brief.priorities.map((w, i) => (
              <button
                key={w.id}
                className={`dr-priority ${focus?.id === w.id ? "active" : ""}`}
                onClick={() => {
                  setSelected(w.id);
                  setTab("evidence");
                }}
              >
                <span className="dr-priority-top">
                  <span>
                    {String(i + 1).padStart(2, "0")} / {w.assetId}
                  </span>
                  <span className={`dr-severity ${w.severity}`}>
                    {w.severity}
                  </span>
                </span>
                <strong>{w.title}</strong>
                <p>
                  {w.assetName} · {w.evidenceCount} evidence items
                </p>
                <span className="dr-priority-bottom">
                  {w.state === "owned" ? "Owner accepted" : "Acceptance needed"}
                  <span>
                    {w.minutes > 0 ? `Due in ${w.minutes}m` : "Due now"}
                  </span>
                </span>
              </button>
            ))
          )}
        </aside>
        <section className="dr-detail">
          <div
            className="dr-tabs"
            role="tablist"
            aria-label="Decision workspace"
          >
            <button
              role="tab"
              aria-selected={tab === "evidence"}
              onClick={() => setTab("evidence")}
            >
              Evidence & next action
            </button>
            <button
              role="tab"
              aria-selected={tab === "rehearsal"}
              onClick={() => setTab("rehearsal")}
            >
              <FlaskConical size={15} /> Maintenance rehearsal
            </button>
          </div>
          <motion.div
            key={tab}
            initial={{ opacity: reduced ? 1 : 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.16, ease: [0.23, 1, 0.32, 1] }}
          >
            {tab === "evidence" ? (
              <div className="dr-detail-body">
                {focus ? (
                  <>
                    <div className="dr-detail-eyebrow">
                      <span>{focus.assetId}</span>
                      <span className="dr-severity">{focus.state}</span>
                    </div>
                    <h2>{focus.title}</h2>
                    <div className="dr-owner">
                      <span className="dr-avatar">
                        {focus.ownerName
                          .split(" ")
                          .map((n) => n[0])
                          .join("")
                          .slice(0, 2)}
                      </span>
                      <span>
                        <strong>{focus.ownerName}</strong>
                        <small>
                          {focus.state === "owned"
                            ? "Ownership accepted"
                            : "Assigned · acceptance pending"}
                        </small>
                      </span>
                      <Link href={`/warnings/${focus.id}`}>
                        Review commitment <ArrowUpRight size={14} />
                      </Link>
                    </div>
                    <div className="dr-next">
                      <p>{focus.nextAction}</p>
                      <Link
                        className="button primary"
                        href={`/investigate/${focus.assetId}`}
                      >
                        Investigate the cause <ArrowRight size={15} />
                      </Link>
                    </div>
                    {asset && (
                      <div className="dr-reading">
                        <div>
                          <span>{asset.metric}</span>
                          <strong>
                            {asset.value.toFixed(1)} <small>{asset.unit}</small>
                          </strong>
                        </div>
                        <Trend
                          values={asset.history}
                          baseline={asset.baseline}
                        />
                        <small>
                          Baseline {asset.baseline} {asset.unit}
                          <br />
                          Recent samples · simulated telemetry
                        </small>
                      </div>
                    )}
                    <h3 className="dr-label">Evidence</h3>
                    <div className="dr-evidence">
                      {focus.evidence.map((e, i) => (
                        <p key={i}>
                          <CheckCheck size={15} />
                          {e}
                        </p>
                      ))}
                      {focus.notes.map((n) => (
                        <p key={n.id}>
                          <CircleDot size={15} />
                          <span>
                            {n.text}
                            <small>Field note · {n.author}</small>
                          </span>
                        </p>
                      ))}
                    </div>
                    <div className="dr-gaps">
                      <TriangleAlert size={16} />
                      <div>
                        <strong>
                          {focus.missing.length
                            ? "Still to verify"
                            : "Evidence collected; follow-through remains open"}
                        </strong>
                        <p>
                          {focus.missing.join(" · ") ||
                            "An inspection does not resolve the underlying warning."}
                        </p>
                      </div>
                    </div>
                  </>
                ) : (
                  <div className="dr-empty">
                    <ShieldCheck size={32} />
                    <h2>Ready for the next decision.</h2>
                    <p>
                      No active warnings in this snapshot. Review your inherited
                      shift context or test a maintenance action.
                    </p>
                    <Link className="button primary" href="/start">
                      Receive shift handover <ArrowRight size={16} />
                    </Link>
                  </div>
                )}
              </div>
            ) : (
              <div className="dr-detail-body">
                <h2>What if this feed goes offline?</h2>
                <p className="dr-description">
                  Simulate an isolation without changing equipment state.
                </p>
                <label className="dr-select">
                  Equipment to isolate
                  <select
                    value={target}
                    onChange={(e) => {
                      setTarget(e.target.value);
                      setResult(null);
                    }}
                  >
                    {state.assets
                      .filter((a) => ["ups", "pdu"].includes(a.type))
                      .map((a) => (
                        <option key={a.id} value={a.id}>
                          {a.name} · {a.status}
                        </option>
                      ))}
                  </select>
                </label>
                <button
                  className="button primary"
                  disabled={busy}
                  onClick={() => void simulate()}
                >
                  <FlaskConical size={16} />
                  {busy ? "Checking power paths…" : "Run rehearsal"}
                </button>
                <div className="dr-power-map">
                  <span className="dr-label">Power paths</span>
                  <div className="dr-power-sources">
                    {state.assets
                      .filter((a) => a.type === "ups")
                      .map((a) => (
                        <div key={a.id}>
                          <Zap size={18} />
                          <strong>{a.id}</strong>
                          <span
                            className={
                              a.status === "online"
                                ? "available"
                                : "unavailable"
                            }
                          >
                            {a.status}
                          </span>
                        </div>
                      ))}
                  </div>
                  <div className="dr-power-lines">
                    <span>via PDU-4</span>
                    <span>alternate feed</span>
                  </div>
                  <div className="dr-power-load">
                    <LayersIcon />
                    <strong>AI Row D</strong>
                    <span>
                      {brief?.topology.find((l) => l.assetId === "Row-D")
                        ?.level ?? "—"}{" "}
                      · modeled source reachability
                    </span>
                  </div>
                </div>
                <AnimatePresence initial={false}>
                  {result && (
                    <motion.div
                      key="rehearsal-result"
                      initial={{
                        opacity: 0,
                        transform: reduced ? "none" : "translateY(6px)",
                      }}
                      animate={{ opacity: 1, transform: "translateY(0px)" }}
                      exit={{ opacity: 0 }}
                      transition={{ duration: 0.18, ease: [0.23, 1, 0.32, 1] }}
                      role="status"
                      className={`dr-result ${result.verdict === "HOLD" ? "hold" : "go"}`}
                    >
                      <strong>
                        {result.verdict === "HOLD"
                          ? "HOLD · Last source at risk"
                          : "PATH RETAINED · Further checks required"}
                      </strong>
                      <p>{result.reason}</p>
                      {result.loads.map((l) => (
                        <div key={l.assetId}>
                          {l.assetId}
                          <span>
                            {l.before} <ArrowRight size={14} /> {l.level}
                          </span>
                        </div>
                      ))}
                      <ul>
                        {result.assumptions.map((a) => (
                          <li key={a}>{a}</li>
                        ))}
                      </ul>
                      <Link
                        href="/procedures?procedure=MOP-UPS&asset=PDU-4"
                        className="text-link"
                      >
                        Open approved procedure <ArrowRight size={14} />
                      </Link>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            )}
          </motion.div>
        </section>
      </div>
      <div className="dr-bottom">
        <Link href="/handover">
          <CheckCheck />
          <div>
            <strong>Handover</strong>
          </div>
          <ArrowUpRight />
        </Link>
        <Link href="/traces">
          <GitBranch />
          <div>
            <strong>Decision traces</strong>
          </div>
          <ArrowUpRight />
        </Link>
      </div>
    </div>
  );
}
function LayersIcon() {
  return <Zap size={22} />;
}
function Trend({ values, baseline }: { values: number[]; baseline: number }) {
  const v = values.length > 1 ? values : [baseline, baseline];
  const min = Math.min(...v, baseline) - 0.1,
    max = Math.max(...v, baseline) + 0.1;
  const y = (n: number) => 65 - ((n - min) / (max - min)) * 50;
  return (
    <svg
      viewBox="0 0 240 80"
      role="img"
      aria-label={`Recent telemetry trend, baseline ${baseline}`}
    >
      <line
        x1="0"
        x2="240"
        y1={y(baseline)}
        y2={y(baseline)}
        stroke="currentColor"
        opacity=".25"
        strokeDasharray="4 4"
      />
      <path
        d={`M ${v.map((n, i) => `${(i / (v.length - 1)) * 240},${y(n)}`).join(" L ")}`}
        fill="none"
        stroke="var(--dr-accent)"
        strokeWidth="2"
      />
    </svg>
  );
}
