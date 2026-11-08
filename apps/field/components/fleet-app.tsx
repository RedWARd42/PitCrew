"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import {
  Activity,
  ArrowRight,
  ArrowUpRight,
  Bell,
  Bot,
  Check,
  CheckCheck,
  ChevronRight,
  Clock3,
  ClipboardList,
  Command,
  GitBranch,
  Layers3,
  LoaderCircle,
  MapPin,
  Pause,
  Play,
  Plus,
  Radio,
  RotateCcw,
  Search,
  Settings2,
  ShieldCheck,
  Signal,
  SlidersHorizontal,
  TriangleAlert,
  Users,
  X,
} from "lucide-react";
import BrandMark from "./brand-mark";
import { ShiftBrief, Upkeep, NextWork } from "./shift-operations";
import { rankTechnicianQueue } from "../../../packages/contracts/work-order";
import type {
  FleetActivity,
  FleetCommand,
  FleetState,
  FleetTicket,
  Sector,
  SectorId,
  Technician,
} from "../../../packages/contracts/fleet";

type Send = (command: FleetCommand) => Promise<boolean>;
const when = (ts: string) =>
  new Date(ts).toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "America/Chicago",
  });
const human = (text: string) => text.replaceAll("_", " ").replaceAll("-", " ");
const ticketLabel = (id: string) =>
  `FW-${id.replaceAll("-", "").slice(-6).toUpperCase()}`;
const mode = (value: string) =>
  value === "live"
    ? "Nemotron · live"
    : value === "fallback"
      ? "Rules · fallback"
      : "Evidence rules";
const initials = (name: string) =>
  name
    .split(" ")
    .map((s) => s[0])
    .slice(0, 2)
    .join("");
const nav = [
  { href: "/", label: "Overview", icon: Layers3 },
  { href: "/tickets", label: "Work queue", icon: ClipboardList },
  { href: "/brief", label: "Shift brief", icon: CheckCheck },
  { href: "/upkeep", label: "Upcoming work", icon: Clock3 },
  { href: "/team", label: "Team & coverage", icon: Users },
  { href: "/activity", label: "Activity", icon: Activity },
];

export default function FleetApp() {
  const pathname = usePathname();
  const [state, setState] = useState<FleetState | null>(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [persona, setPersona] = useState("maria"),
    [controls, setControls] = useState(false),
    [notices, setNotices] = useState(false);
  const pending = useRef(false),
    mounted = useRef(true);
  const requestGeneration = useRef(0);
  const reduced = useReducedMotion();
  const refresh = useCallback(async () => {
    if (pending.current) return;
    const generation = requestGeneration.current;
    try {
      const r = await fetch("/api/fleet", { cache: "no-store" });
      if (!r.ok) throw Error("Could not connect to the sector teams.");
      const data = await r.json();
      if (
        mounted.current &&
        !pending.current &&
        generation === requestGeneration.current
      ) {
        setState(data);
        setError("");
      }
    } catch (e) {
      if (mounted.current && generation === requestGeneration.current)
        setError(e instanceof Error ? e.message : "Connection unavailable");
    }
  }, []);
  useEffect(() => {
    mounted.current = true;
    const saved = localStorage.getItem("groundtruth-fleet-persona");
    if (saved) setPersona(saved);
    void refresh();
    const interval = setInterval(() => void refresh(), 2500);
    return () => {
      mounted.current = false;
      clearInterval(interval);
    };
  }, [refresh]);
  async function send(command: FleetCommand) {
    if (pending.current) return false;
    requestGeneration.current += 1;
    pending.current = true;
    setBusy(true);
    setError("");
    try {
      const r = await fetch("/api/fleet", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(command),
      });
      const data = await r.json();
      if (!r.ok) throw Error(data.error ?? "Action could not be completed.");
      setState(data);
      return true;
    } catch (e) {
      setError(e instanceof Error ? e.message : "Action unavailable");
      return false;
    } finally {
      pending.current = false;
      setBusy(false);
    }
  }
  const selectPersona = (id: string) => {
    setPersona(id);
    localStorage.setItem("groundtruth-fleet-persona", id);
    setNotices(false);
  };
  if (!state)
    return (
      <div className="fl-loading">
        <BrandMark />
        <h1>PitCrew</h1>
        <p>{error || "Connecting to your sector teams…"}</p>
        {error && <button onClick={() => void refresh()}>Try again</button>}
      </div>
    );
  const me =
    state.technicians.find((t) => t.id === persona) ?? state.technicians[0];
  const mine = state.tickets.filter(
    (t) => t.assigneeId === me?.id && t.status !== "resolved",
  );
  const notifications = state.notifications.filter(
    (n) => n.technicianId === me?.id,
  );
  const unread = notifications.filter((n) => !n.read).length;
  const parts = pathname.split("/").filter(Boolean);
  const sector = state.sectors.find((s) => s.id === parts[1]);
  const ticket = state.tickets.find(
    (t) => t.id === decodeURIComponent(parts[1] ?? ""),
  );
  const title =
    parts[0] === "tickets"
      ? ticket
        ? "Field work"
        : "Work queue"
      : parts[0] === "brief"
        ? "Shift brief"
        : parts[0] === "upkeep"
          ? "Upcoming work"
          : parts[0] === "team"
            ? "Team & coverage"
            : parts[0] === "activity"
              ? "Activity"
              : parts[0] === "sectors"
                ? (sector?.name ?? "Sector")
                : "Response center";
  return (
    <div className="fl-shell">
      <aside className="fl-sidebar">
        <Link href="/" className="fl-brand">
          <BrandMark />
          PitCrew
        </Link>
        <div className="fl-site">
          <div>
            <Layers3 size={18} />
          </div>
          <span>
            <strong>NMC² · Dallas</strong>
            <small>DAL-1 / three sectors</small>
          </span>
          <ChevronRight size={14} />
        </div>
        <nav aria-label="Main navigation">
          {nav.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              className={
                (
                  n.href === "/"
                    ? pathname === "/"
                    : pathname.startsWith(n.href)
                )
                  ? "active"
                  : ""
              }
            >
              <n.icon size={18} />
              {n.label}
              {n.href === "/tickets" && mine.length > 0 && (
                <span className="fl-count">{mine.length}</span>
              )}
            </Link>
          ))}
        </nav>
        <div className="fl-sidebar-sectors">
          <span>Sectors</span>
          {state.sectors.map((s) => (
            <Link
              href={`/sectors/${s.id}`}
              key={s.id}
              className={sector?.id === s.id ? "active" : ""}
            >
              <span className={`fl-dot ${s.status}`} />
              {s.name}
              <small>
                {state.agents.filter(
                  (a) => a.sectorId === s.id && a.status === "working",
                ).length
                  ? "Working"
                  : human(s.status)}
              </small>
            </Link>
          ))}
        </div>
        <div className="fl-sidebar-foot">
          <div className="fl-system">
            <ShieldCheck size={16} />
            <span>
              Advisory operations
              <small>Simulated facility · real workflows</small>
            </span>
          </div>
          <Link href="/team" className="fl-profile">
            <span className="fl-avatar">{initials(me?.name ?? "M")}</span>
            <span>
              <strong>{me?.name}</strong>
              <small>Checked in · Sector {me?.checkedInSector}</small>
            </span>
            <Settings2 size={16} />
          </Link>
        </div>
      </aside>
      <div className="fl-workspace">
        <header className="fl-topbar">
          <div className="fl-breadcrumb">
            <span>DAL-1</span>
            <ChevronRight size={12} />
            <span>{title}</span>
          </div>
          <div className="fl-topbar-actions">
            <span className="fl-clock">
              Simulated vitals ·{" "}
              {state.useModel ? "Nemotron enabled" : "Rules mode"}
              <Clock3 size={13} />
              {when(state.clock)}
            </span>
            <div className="fl-persona">
              <label htmlFor="fl-persona">View as</label>
              <select
                id="fl-persona"
                value={me?.id}
                onChange={(e) => selectPersona(e.target.value)}
              >
                {state.technicians.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name}
                  </option>
                ))}
              </select>
            </div>
            <button
              className="fl-icon-button"
              aria-label="Notifications"
              aria-expanded={notices}
              onClick={() => setNotices(!notices)}
            >
              <Bell size={18} />
              {unread > 0 && (
                <span className="fl-notification-count">{unread}</span>
              )}
            </button>
            <button
              className={`fl-icon-button ${controls ? "active" : ""}`}
              aria-label="Demo controls"
              aria-expanded={controls}
              onClick={() => setControls(!controls)}
            >
              <SlidersHorizontal size={18} />
            </button>
          </div>
        </header>
        {notices && (
          <div className="fl-notifications">
            <div>
              <h3>Your notifications</h3>
              <button
                aria-label="Close notifications"
                onClick={() => setNotices(false)}
              >
                <X size={16} />
              </button>
            </div>
            {notifications.length ? (
              notifications
                .slice()
                .reverse()
                .slice(0, 8)
                .map((n) => (
                  <Link
                    href={`/tickets/${n.ticketId}`}
                    key={n.id}
                    onClick={() => {
                      void send({
                        type: "read_notification",
                        notificationId: n.id,
                        technicianId: me.id,
                      });
                      setNotices(false);
                    }}
                  >
                    <span className={`fl-dot ${n.read ? "" : "watch"}`} />
                    <span>
                      {n.text}
                      <small>
                        Sector {n.sectorId} · {when(n.ts)}
                      </small>
                    </span>
                    <ArrowUpRight size={14} />
                  </Link>
                ))
            ) : (
              <p>No notifications yet. Ticket offers will appear here.</p>
            )}
          </div>
        )}
        <div className="fl-main">
          <AnimatePresence initial={false}>
            {controls && (
              <motion.section
                className="fl-demo"
                initial={{
                  opacity: 0,
                  transform: reduced ? "none" : "translateY(-4px)",
                }}
                animate={{ opacity: 1, transform: "translateY(0px)" }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.16 }}
              >
                <div className="fl-demo-heading">
                  <h3>Demo controls</h3>
                  <span>Changes affect this shared demo</span>
                  <button
                    aria-label="Close demo controls"
                    onClick={() => setControls(false)}
                  >
                    <X size={15} />
                  </button>
                </div>
                <div className="fl-scenarios">
                  {(
                    [
                      ["normal", "Normal operations"],
                      ["cooling", "Cooling drift"],
                      ["sensor", "Sensor mismatch"],
                      ["uncovered", "No sector coverage"],
                      ["upkeep", "Preventive work"],
                    ] as const
                  ).map(([id, label]) => (
                    <button
                      key={id}
                      disabled={busy}
                      className={state.scenario === id ? "selected" : ""}
                      onClick={() =>
                        void send({ type: "scenario", scenario: id })
                      }
                    >
                      {label}
                      <ArrowUpRight size={13} />
                    </button>
                  ))}
                </div>
                <div className="fl-demo-bottom">
                  <button
                    disabled={busy}
                    onClick={() =>
                      void send({ type: "monitor", running: !state.running })
                    }
                  >
                    {state.running ? <Pause size={14} /> : <Play size={14} />}{" "}
                    {state.running ? "Pause monitoring" : "Start monitoring"}
                  </button>
                  <button
                    disabled={busy}
                    onClick={() => void send({ type: "tick", seconds: 60 })}
                  >
                    <Clock3 size={14} />
                    Advance 60 seconds
                  </button>
                  <label>
                    <input
                      type="checkbox"
                      checked={state.useModel}
                      disabled={busy}
                      onChange={(e) =>
                        void send({ type: "model", enabled: e.target.checked })
                      }
                    />
                    Live Nemotron
                  </label>
                  <button
                    disabled={busy}
                    onClick={() => void send({ type: "reset" })}
                  >
                    <RotateCcw size={14} />
                    Reset
                  </button>
                </div>
                {state.useModel && (
                  <p>
                    Seeded readings and synthetic field evidence are sent to
                    NVIDIA.{" "}
                    {state.modelConfigured
                      ? ""
                      : "No API key configured; the app will use labeled fallback rules."}
                  </p>
                )}
              </motion.section>
            )}
          </AnimatePresence>
          {error && (
            <div className="fl-error" role="alert">
              <TriangleAlert size={17} />
              {error}
              <button aria-label="Dismiss error" onClick={() => setError("")}>
                <X size={16} />
              </button>
            </div>
          )}
          <div className="fl-page-title">
            <div>
              <h1>{title}</h1>
              {parts[0] === "tickets" && ticket && (
                <span>
                  {ticketLabel(ticket.id)} · Sector {ticket.sectorId}
                </span>
              )}
            </div>
            <span className="fl-live-state">
              <span className={`fl-dot ${state.running ? "active" : ""}`} />
              {state.running ? "Monitoring active" : "Monitoring paused"}
            </span>
          </div>
          {(parts.length === 0 || parts[0] === "fleet") && (
            <Overview
              state={state}
              me={me}
              send={send}
              busy={busy}
              openControls={() => setControls(true)}
            />
          )}
          {parts[0] === "sectors" &&
            (sector ? (
              <SectorView
                state={state}
                sector={sector}
                send={send}
                busy={busy}
              />
            ) : (
              <Empty
                title="Sector not found"
                text="Return to the facility overview to select a sector."
              />
            ))}
          {parts[0] === "tickets" &&
            (parts[1] ? (
              ticket ? (
                <TicketView
                  key={ticket.id}
                  ticket={ticket}
                  state={state}
                  me={me}
                  send={send}
                  busy={busy}
                />
              ) : (
                <Empty
                  title="Ticket not found"
                  text="This ticket may have belonged to a scenario that was reset."
                />
              )
            ) : (
              <WorkQueue state={state} me={me} />
            ))}
          {parts[0] === "brief" && (
            <ShiftBrief state={state} me={me} send={send} busy={busy} />
          )}
          {parts[0] === "upkeep" && (
            <Upkeep state={state} me={me} send={send} busy={busy} />
          )}
          {parts[0] === "team" && (
            <Team state={state} me={me} send={send} busy={busy} />
          )}
          {parts[0] === "activity" && <ActivityView state={state} />}
          <footer className="fl-footer">
            <span>
              <ShieldCheck size={13} />
              No plant controls connected
            </span>
            <span>
              {state.useModel ? "Nemotron enabled" : "Deterministic demo"} ·
              simulated notifications
            </span>
          </footer>
        </div>
      </div>
      <nav className="fl-mobile-nav" aria-label="Mobile navigation">
        {nav.map((n) => (
          <Link
            key={n.href}
            href={n.href}
            className={
              (n.href === "/" ? pathname === "/" : pathname.startsWith(n.href))
                ? "active"
                : ""
            }
          >
            <n.icon size={19} />
            <span>
              {n.href === "/"
                ? "Overview"
                : n.href === "/tickets"
                  ? "My work"
                  : n.href === "/brief"
                    ? "Brief"
                    : n.href === "/upkeep"
                      ? "Upkeep"
                      : n.href === "/team"
                        ? "Team"
                        : "Activity"}
            </span>
          </Link>
        ))}
      </nav>
    </div>
  );
}

function Overview({
  state,
  me,
  send,
  busy,
  openControls,
}: {
  state: FleetState;
  me: Technician;
  send: Send;
  busy: boolean;
  openControls: () => void;
}) {
  const active = state.tickets.filter((t) => t.status !== "resolved"),
    mine = active.filter((t) => t.assigneeId === me.id),
    working = state.agents.filter((a) => a.status === "working");
  const [selected, setSelected] = useState<SectorId>("A");
  const sector =
    state.sectors.find((s) => s.id === selected) ?? state.sectors[0];
  const current = mine[0] ?? active[0];
  const incident = current
    ? state.incidents.find((i) => i.id === current.incidentId)
    : state.incidents.at(-1);
  const agentOnly =
    !!incident &&
    incident.status === "monitoring" &&
    incident.kind !== "maintenance" &&
    state.activity.some(
      (item) =>
        item.incidentId === incident.id &&
        item.action === "telemetry.refreshed",
    ) &&
    !state.tickets.some((t) => t.incidentId === incident.id);
  const responder = state.technicians.find((t) => t.id === current?.assigneeId);
  const stepCount = current?.steps.filter((s) => s.completed).length ?? 0;
  const journey = [
    {
      label: "Signal",
      icon: Radio,
      ready: !!incident,
      detail: incident
        ? `Sector ${incident.sectorId} · ${incident.assetId}`
        : "Sector agents watch for drift",
    },
    {
      label: "Investigation",
      icon: Search,
      ready: !!incident && incident.status !== "investigating",
      detail: working.length
        ? "Gathering and checking evidence"
        : incident
          ? agentOnly
            ? "Evidence checked; monitoring continues"
            : "Diagnosis and evidence attached"
          : "Correlate evidence before dispatch",
    },
    {
      label: "Field response",
      icon: ClipboardList,
      ready: !!current && ["accepted", "in_progress"].includes(current.status),
      detail: current
        ? `${responder?.name ?? "Finding responder"} · ${stepCount}/${current.steps.length} checks`
        : agentOnly
          ? "No physical work required"
          : "Send a qualified, equipped responder",
    },
    {
      label: "Handoff",
      icon: GitBranch,
      ready: !!current?.escalationLevel,
      detail: current?.escalationLevel
        ? `${stepCount} completed checks carried forward`
        : agentOnly
          ? "Findings retained in shared memory"
          : "Carry completed work to the next responder",
    },
  ];
  return (
    <>
      <ShiftBrief compact state={state} me={me} send={send} busy={busy} />
      <section className="fl-response">
        <div className="fl-response-main">
          <div className="fl-response-copy">
            <h2>
              {current
                ? current.title
                : working.length
                  ? "Investigating before sending someone."
                  : agentOnly
                    ? "No field visit needed."
                    : "From first signal to the right response."}
            </h2>
            <p>
              {current
                ? current.escalationLevel
                  ? current.handoff.summary
                  : current.dispatchReason
                : working.length
                  ? "Agents are checking telemetry, prior work, and equipment evidence. A field ticket is created only when physical work is needed."
                  : agentOnly
                    ? "The sector team refreshed the simulated collector and verified agreement with the redundant feed. No technician ticket was created."
                    : "Agents investigate the issue, prepare the job, and find the right technician. Every completed check travels with the case."}
            </p>
            {current ? (
              <Link
                className="fl-button fl-primary"
                href={`/tickets/${current.id}`}
              >
                {current.assigneeId === me.id
                  ? ["offered", "escalated"].includes(current.status)
                    ? "Review & accept assignment"
                    : "Continue field work"
                  : `View ${responder?.name.split(" ")[0] ?? "responder"}’s assignment`}
                <ArrowRight size={16} />
              </Link>
            ) : agentOnly ? (
              <Link className="fl-button fl-primary" href="/activity">
                Inspect agent work
                <ArrowRight size={16} />
              </Link>
            ) : working.length ? (
              <Link className="fl-button fl-secondary" href="/activity">
                <LoaderCircle className="fl-spin" size={15} />
                Follow investigation
              </Link>
            ) : (
              <button
                className="fl-button fl-primary"
                disabled={busy}
                onClick={() =>
                  void send({ type: "scenario", scenario: "cooling" })
                }
              >
                Run a response scenario
                <ArrowRight size={16} />
              </button>
            )}
          </div>
          <div className="fl-response-state">
            <span className="fl-response-symbol">
              {current ? (
                <ClipboardList size={28} />
              ) : working.length ? (
                <Search size={28} />
              ) : (
                <GitBranch size={28} />
              )}
            </span>
            <strong>
              {current
                ? ticketLabel(current.id)
                : working.length
                  ? "Investigation in progress"
                  : agentOnly
                    ? "Agent-only response"
                    : "Cooling drift scenario"}
            </strong>
            <span>
              {current
                ? `${responder?.name ?? "On-call responder"} · Sector ${current.sectorId}`
                : working.length
                  ? `${working.length} agents working together`
                  : agentOnly
                    ? "Technician capacity preserved"
                    : "One case, from detection to handoff"}
            </span>
            {current && (
              <span className="fl-badge">{human(current.status)}</span>
            )}
          </div>
        </div>
        <div className="fl-journey">
          {journey.map((j, i) => (
            <div key={j.label} className={j.ready ? "complete" : ""}>
              <span className="fl-journey-icon">
                {j.ready ? <Check size={15} /> : <j.icon size={15} />}
              </span>
              <div>
                <strong>{j.label}</strong>
                <p>{j.detail}</p>
              </div>
              {i < journey.length - 1 && (
                <ChevronRight className="fl-journey-arrow" size={14} />
              )}
            </div>
          ))}
        </div>
      </section>
      <div className="fl-overview-grid">
        <section className="fl-facility">
          <div className="fl-section-head">
            <h2>Sector coverage</h2>
            <button className="fl-text-button" onClick={openControls}>
              Run a scenario
              <ArrowUpRight size={13} />
            </button>
          </div>
          <div className="fl-sector-grid">
            {state.sectors.map((s) => (
              <button
                key={s.id}
                className={`fl-sector-card ${selected === s.id ? "selected" : ""} ${s.status}`}
                onClick={() => setSelected(s.id)}
              >
                <div className="fl-sector-card-top">
                  <strong>Sector {s.id}</strong>
                  <span className="fl-badge">
                    <span className={`fl-dot ${s.status}`} />
                    {human(s.status)}
                  </span>
                </div>
                <div className="fl-racks" aria-hidden="true">
                  {[0, 1, 2, 3].map((i) => (
                    <div className="fl-rack" key={i}>
                      {[0, 1, 2, 3, 4, 5].map((j) => (
                        <i key={j}>
                          <b />
                        </i>
                      ))}
                    </div>
                  ))}
                </div>
                <h3>{s.name}</h3>
                <span className="fl-sector-asset-count">
                  {s.assets.length} assets ·{" "}
                  {state.agents.filter((a) => a.sectorId === s.id).length}{" "}
                  agents
                </span>
                <div className="fl-sector-spark">
                  <Spark values={s.assets[0]?.history ?? []} />
                  <strong>
                    {s.assets[0]?.value.toFixed(1)}
                    <small>{s.assets[0]?.unit}</small>
                  </strong>
                </div>
              </button>
            ))}
          </div>
          <div className="fl-map-key">
            <span>
              <span className="fl-dot stable" />
              Stable
            </span>
            <span>
              <span className="fl-dot watch" />
              Needs attention
            </span>
            <Link href={`/sectors/${selected}`}>
              Open Sector {selected}
              <ArrowRight size={14} />
            </Link>
          </div>
        </section>
        <section className="fl-panel fl-agent-panel">
          <div className="fl-section-head">
            <h2>Sector {selected} team</h2>
            <span className="fl-badge">Shared context</span>
          </div>
          <AgentTeam state={state} sectorId={selected} />
          <div className="fl-agent-context">
            <GitBranch size={17} />
            <div>
              <strong>One shared memory</strong>
              <p>
                {sector.memory.at(-1)?.text ??
                  "The team shares observations, diagnoses, and completed work for this sector."}
              </p>
            </div>
          </div>
          <Link href={`/sectors/${selected}`} className="fl-panel-link">
            See evidence & memory
            <ArrowRight size={15} />
          </Link>
        </section>
      </div>
      <div className="fl-bottom-grid">
        <section>
          <div className="fl-section-head">
            <h2>Field work</h2>
            <Link href="/tickets">
              All tickets
              <ArrowUpRight size={14} />
            </Link>
          </div>
          {active.length ? (
            <div className="fl-ticket-list">
              {active.slice(0, 3).map((t) => (
                <TicketCard key={t.id} ticket={t} state={state} />
              ))}
            </div>
          ) : (
            <div className="fl-empty-work">
              <div className="fl-empty-icon">
                <ShieldCheck size={26} />
              </div>
              <h3>No physical work needed.</h3>
              <p>
                {working.length
                  ? "An agent team is gathering evidence. A ticket appears only if a technician is needed."
                  : "Agents investigate first. Only work that needs someone on the floor becomes a ticket."}
              </p>
              <button
                className="fl-button fl-primary"
                disabled={busy}
                onClick={() =>
                  void send({ type: "scenario", scenario: "cooling" })
                }
              >
                {working.length ? (
                  <LoaderCircle className="fl-spin" size={15} />
                ) : (
                  <Plus size={15} />
                )}
                Introduce cooling drift
              </button>
            </div>
          )}
        </section>
        <section>
          <div className="fl-section-head">
            <h2>Latest activity</h2>
            <Link href="/activity">
              Full log
              <ArrowUpRight size={14} />
            </Link>
          </div>
          <div className="fl-activity-preview">
            {state.activity.length ? (
              state.activity
                .slice(-5)
                .reverse()
                .map((a) => <ActivityRow entry={a} key={a.id} compact />)
            ) : (
              <Empty
                title="Ready to monitor"
                text="Agent tool calls and technician actions will appear here."
              />
            )}
          </div>
        </section>
      </div>
    </>
  );
}
function AgentTeam({
  state,
  sectorId,
}: {
  state: FleetState;
  sectorId: SectorId;
}) {
  return (
    <div className="fl-agents">
      {state.agents
        .filter((a) => a.sectorId === sectorId)
        .map((a) => (
          <div
            key={a.id}
            className={`fl-agent ${a.status === "working" ? "working" : ""}`}
          >
            <span className="fl-agent-icon">
              {a.role === "sentinel" ? (
                <Radio size={18} />
              ) : a.role === "investigator" ? (
                <Search size={18} />
              ) : (
                <GitBranch size={18} />
              )}
            </span>
            <div>
              <div>
                <strong>{a.name}</strong>
                <span>
                  {a.status === "working" ? (
                    <LoaderCircle className="fl-spin" size={11} />
                  ) : (
                    <span className="fl-tiny-dot" />
                  )}
                  {human(a.status)}
                </span>
              </div>
              <p>{a.lastAction}</p>
              <small>
                {a.role === "sentinel" ? "Telemetry rules" : mode(a.mode)}
              </small>
            </div>
          </div>
        ))}
    </div>
  );
}
function Spark({ values }: { values: number[] }) {
  const data = values.length > 1 ? values : [0, 0],
    lo = Math.min(...data) - 0.2,
    hi = Math.max(...data) + 0.2;
  return (
    <svg
      viewBox="0 0 170 44"
      role="img"
      aria-label="Recent telemetry trend"
      preserveAspectRatio="none"
    >
      <path
        d={`M ${data.map((v, i) => `${(i / (data.length - 1)) * 170},${39 - ((v - lo) / (hi - lo)) * 34}`).join(" L ")}`}
        fill="none"
        stroke="currentColor"
        strokeWidth="1.6"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}
function TicketCard({
  ticket: t,
  state,
}: {
  ticket: FleetTicket;
  state: FleetState;
}) {
  const owner = state.technicians.find((p) => p.id === t.assigneeId);
  return (
    <Link className={`fl-ticket-card ${t.priority}`} href={`/tickets/${t.id}`}>
      <div className="fl-ticket-icon">
        <ClipboardList size={20} />
      </div>
      <div className="fl-ticket-card-copy">
        <div>
          <span>
            {ticketLabel(t.id)} · Sector {t.sectorId}
          </span>
          <span className="fl-badge">{human(t.status)}</span>
        </div>
        <h3>{t.title}</h3>
        <p>{t.summary}</p>
        <div className="fl-ticket-meta">
          <span>
            <MapPin size={12} />
            {t.assetId}
          </span>
          <span>
            <span className="fl-avatar mini">
              {initials(owner?.name ?? "?")}
            </span>
            {owner?.name ?? "Escalating to on-call"}
          </span>
          <span>
            {t.steps.filter((s) => s.completed).length}/{t.steps.length} checks
          </span>
        </div>
      </div>
      <ArrowUpRight size={16} />
    </Link>
  );
}
function SectorView({
  state,
  sector,
  send,
  busy,
}: {
  state: FleetState;
  sector: Sector;
  send: Send;
  busy: boolean;
}) {
  return (
    <>
      <div className="fl-sector-toolbar">
        <span className="fl-badge">
          <span className={`fl-dot ${sector.status}`} />
          {human(sector.status)}
        </span>
        <span>{sector.description}</span>
        <button
          className="fl-button fl-secondary"
          disabled={
            busy ||
            state.agents.some(
              (a) => a.sectorId === sector.id && a.status === "working",
            )
          }
          onClick={() =>
            void send({ type: "investigate", sectorId: sector.id })
          }
        >
          <Search size={15} />
          Investigate sector
        </button>
      </div>
      <div className="fl-vitals">
        {sector.assets.map((a) => (
          <article key={a.id}>
            <div>
              <span>{a.name}</span>
              <span className="fl-badge">{human(a.status)}</span>
            </div>
            <strong>
              {a.value.toFixed(1)}
              <small>{a.unit}</small>
            </strong>
            <p>{a.metric}</p>
            <Spark values={a.history} />
            <small>
              Baseline {a.baseline} · limit {a.limit} {a.unit}
            </small>
          </article>
        ))}
      </div>
      <div className="fl-bottom-grid">
        <section className="fl-panel">
          <div className="fl-section-head">
            <h2>Agent team</h2>
          </div>
          <AgentTeam state={state} sectorId={sector.id} />
        </section>
        <section className="fl-panel">
          <div className="fl-section-head">
            <h2>Shared memory</h2>
            <span>{sector.memory.length} records</span>
          </div>
          <div className="fl-memory">
            {sector.memory.length ? (
              sector.memory
                .slice()
                .reverse()
                .map((m) => (
                  <article key={m.id}>
                    <div>
                      <span className="fl-avatar mini">
                        {m.kind === "handoff" ? (
                          <ArrowRight size={12} />
                        ) : (
                          <GitBranch size={12} />
                        )}
                      </span>
                      <strong>{m.author}</strong>
                      <small>{when(m.ts)}</small>
                    </div>
                    <p>{m.text}</p>
                    <span>{human(m.kind)}</span>
                  </article>
                ))
            ) : (
              <Empty
                title="No open context"
                text="Evidence and actions will be shared here as the team works."
              />
            )}
          </div>
        </section>
      </div>
      <div className="fl-section-head">
        <h2>Sector work</h2>
      </div>
      <div className="fl-ticket-list">
        {state.tickets
          .filter((t) => t.sectorId === sector.id)
          .map((t) => (
            <TicketCard key={t.id} ticket={t} state={state} />
          ))}
      </div>
    </>
  );
}
function WorkQueue({ state, me }: { state: FleetState; me: Technician }) {
  const [filter, setFilter] = useState<"mine" | "all" | "resolved">("mine");
  const sorted =
    filter === "mine"
      ? rankTechnicianQueue(state, me.id)
      : [...state.tickets].sort(
          (a, b) =>
            Number(b.priority === "critical") -
              Number(a.priority === "critical") ||
            Date.parse(a.dueAt ?? a.createdAt) -
              Date.parse(b.dueAt ?? b.createdAt),
        );
  const tickets = sorted.filter((t) =>
    filter === "resolved"
      ? t.status === "resolved"
      : t.status !== "resolved" && (filter === "all" || t.assigneeId === me.id),
  );
  const remainingTickets = filter === "mine" ? tickets.slice(1) : tickets;
  return (
    <>
      {filter === "mine" && <NextWork state={state} me={me} />}
      <div className="fl-tabbar">
        {(["mine", "all", "resolved"] as const).map((f) => (
          <button
            key={f}
            className={filter === f ? "active" : ""}
            onClick={() => setFilter(f)}
          >
            {f === "mine"
              ? "Assigned to me"
              : f === "all"
                ? "All open work"
                : "Completed"}
          </button>
        ))}
      </div>
      {remainingTickets.length ? (
        <div className="fl-ticket-list">
          {remainingTickets.map((t) => (
            <TicketCard key={t.id} ticket={t} state={state} />
          ))}
        </div>
      ) : filter === "mine" ? (
        <p className="op-queue-empty">
          {tickets.length
            ? "No other assignments. Your next action is above."
            : "New qualified assignments will appear here."}
        </p>
      ) : (
        <Empty
          title="No tickets here."
          text="Sector teams create tickets when physical work is required."
        />
      )}
    </>
  );
}
function TicketView({
  ticket: t,
  state,
  me,
  send,
  busy,
}: {
  ticket: FleetTicket;
  state: FleetState;
  me: Technician;
  send: Send;
  busy: boolean;
}) {
  const [note, setNote] = useState(""),
    [reason, setReason] = useState(""),
    [stepNotes, setStepNotes] = useState<Record<string, string>>({});
  const owner = state.technicians.find((p) => p.id === t.assigneeId),
    incident = state.incidents.find((i) => i.id === t.incidentId),
    mine = t.assigneeId === me.id,
    accepted = ["accepted", "in_progress"].includes(t.status),
    complete = t.steps.every((s) => s.completed),
    logs = state.activity.filter(
      (a) => a.ticketId === t.id || a.incidentId === t.incidentId,
    );
  const outsideWindow =
    t.kind === "maintenance" &&
    ((!!t.windowStart && Date.parse(state.clock) < Date.parse(t.windowStart)) ||
      (!!t.windowEnd && Date.parse(state.clock) >= Date.parse(t.windowEnd)));
  return (
    <div className="fl-ticket-detail">
      <section className="fl-ticket-main">
        <div className="fl-ticket-heading">
          <div>
            <span className="fl-badge">{human(t.status)}</span>
            <span className="fl-badge">
              {t.priority === "critical"
                ? "Priority response"
                : t.kind === "maintenance"
                  ? "Scheduled inspection"
                  : "Preventive response"}
            </span>
          </div>
          <h2>{t.title}</h2>
          {t.maintenancePlanId && (
            <p className="ops-ticket-window">
              <Clock3 size={14} />
              Window {t.windowStart ? when(t.windowStart) : "—"}–
              {t.windowEnd ? when(t.windowEnd) : "—"} · Due{" "}
              {t.dueAt ? when(t.dueAt) : "—"}
              <Link href="/upkeep">View plan</Link>
            </p>
          )}
          {outsideWindow && t.status !== "resolved" && (
            <p className="fl-not-your-ticket">
              The approved work window is closed. Preserve findings and
              coordinate the next window before continuing physical checks.
            </p>
          )}
          <div className="fl-assignee">
            <span className="fl-avatar">{initials(owner?.name ?? "?")}</span>
            <div>
              <strong>{owner?.name ?? "Awaiting qualified responder"}</strong>
              <small>
                Sector {t.sectorId} · {human(t.requiredSkill)} ·{" "}
                {t.requiredEquipment.join(" + ")}
              </small>
            </div>
          </div>
          {mine && ["offered", "escalated"].includes(t.status) && (
            <button
              className="fl-button fl-primary"
              disabled={busy || outsideWindow}
              onClick={() =>
                void send({
                  type: "accept",
                  ticketId: t.id,
                  technicianId: me.id,
                })
              }
            >
              Accept assignment
              <ArrowRight size={16} />
            </button>
          )}
          <details className="fl-case-summary">
            <summary>Case brief</summary>
            <p>{t.summary}</p>
          </details>
          {!mine && t.status !== "resolved" && (
            <p className="fl-not-your-ticket">
              Viewing {owner?.name ?? "unassigned"}’s work. Switch “View as” to
              the assigned technician to act.
            </p>
          )}
        </div>
        <div className="fl-ticket-section fl-investigation">
          <h3>
            <Search size={17} />
            {t.kind === "maintenance"
              ? "Work preparation"
              : "Investigation so far"}
          </h3>
          <p>{incident?.hypothesis ?? t.summary}</p>
          {incident?.uncertainty && (
            <div className="fl-caution">
              <TriangleAlert size={15} />
              {incident.uncertainty}
            </div>
          )}
          <span className="fl-provenance">
            {mode(incident?.mode ?? "deterministic")}
          </span>
          <details className="fl-tool-detail">
            <summary>
              Agent evidence and tool calls{" "}
              <span>{logs.filter((a) => a.actorType === "agent").length}</span>
            </summary>
            {logs
              .filter((a) => a.actorType === "agent")
              .map((a) => (
                <ActivityRow entry={a} key={a.id} />
              ))}
          </details>
        </div>
        {t.escalationLevel > 0 && (
          <div className="fl-handoff">
            <div className="fl-section-head">
              <h3>
                <CheckCheck size={18} />
                Handoff brief
              </h3>
              <span>{when(t.handoff.generatedAt)}</span>
            </div>
            <p>{t.handoff.summary}</p>
            <div>
              <section>
                <h4>Already done</h4>
                {t.handoff.completed.length ? (
                  t.handoff.completed.map((s, i) => (
                    <p key={i}>
                      <Check size={13} />
                      {s}
                    </p>
                  ))
                ) : (
                  <p>No physical checks recorded yet.</p>
                )}
              </section>
              <section>
                <h4>Pick up here</h4>
                {t.handoff.remaining.map((s, i) => (
                  <p key={i}>
                    <ArrowRight size={13} />
                    {s}
                  </p>
                ))}
              </section>
            </div>
            {t.handoff.cautions.map((c, i) => (
              <small key={i}>{c}</small>
            ))}
          </div>
        )}
        <div className="fl-ticket-section fl-field-checklist">
          <div className="fl-section-head">
            <h3>Field checklist</h3>
            <span>
              {t.steps.filter((s) => s.completed).length} of {t.steps.length}{" "}
              complete
            </span>
          </div>
          <div className="fl-steps">
            {t.steps.map((s, i) => (
              <article key={s.id} className={s.completed ? "complete" : ""}>
                <span className="fl-step-number">
                  {s.completed ? <Check size={16} /> : i + 1}
                </span>
                <div>
                  <h4>{s.label}</h4>
                  {s.completed ? (
                    <>
                      <small>
                        {state.technicians.find((p) => p.id === s.completedBy)
                          ?.name ?? s.completedBy}{" "}
                        · {s.completedAt ? when(s.completedAt) : "Recorded"}
                      </small>
                      {s.note && <p>{s.note}</p>}
                    </>
                  ) : (
                    <>
                      <label className="fl-sr-only" htmlFor={`note-${s.id}`}>
                        Observation for {s.label}
                      </label>
                      <textarea
                        id={`note-${s.id}`}
                        rows={2}
                        maxLength={1500}
                        disabled={!mine || !accepted || busy || outsideWindow}
                        placeholder="Add what you found (optional)"
                        value={stepNotes[s.id] ?? ""}
                        onChange={(e) =>
                          setStepNotes({ ...stepNotes, [s.id]: e.target.value })
                        }
                      />
                      <button
                        className="fl-button fl-secondary"
                        disabled={!mine || !accepted || busy || outsideWindow}
                        onClick={() =>
                          void send({
                            type: "step",
                            ticketId: t.id,
                            stepId: s.id,
                            technicianId: me.id,
                            note: stepNotes[s.id] ?? "",
                          })
                        }
                      >
                        Record completed check
                        <Check size={14} />
                      </button>
                    </>
                  )}
                </div>
              </article>
            ))}
          </div>
          {mine && accepted && complete && (
            <button
              className="fl-button fl-primary"
              disabled={busy}
              onClick={() =>
                void send({
                  type: "resolve",
                  ticketId: t.id,
                  technicianId: me.id,
                })
              }
            >
              Close completed work
              <CheckCheck size={16} />
            </button>
          )}
          {t.status === "resolved" && (
            <div className="fl-resolved">
              <CheckCheck size={19} />
              Field work completed and recorded.
            </div>
          )}
        </div>
        {mine && accepted && (
          <div className="fl-ticket-section fl-field-actions">
            <details>
              <summary>
                <Plus size={15} />
                Add a field note
              </summary>
              <form
                onSubmit={async (e) => {
                  e.preventDefault();
                  if (
                    await send({
                      type: "note",
                      ticketId: t.id,
                      technicianId: me.id,
                      text: note,
                    })
                  )
                    setNote("");
                }}
              >
                <label htmlFor="fl-field-note">
                  What should the next technician know?
                </label>
                <textarea
                  id="fl-field-note"
                  value={note}
                  maxLength={1500}
                  rows={3}
                  onChange={(e) => setNote(e.target.value)}
                  required
                />
                <button
                  className="fl-button fl-secondary"
                  disabled={busy || !note.trim()}
                >
                  Save to shared memory
                </button>
              </form>
            </details>
            <details>
              <summary>
                <ArrowUpRight size={15} />
                Request senior support
              </summary>
              <form
                onSubmit={async (e) => {
                  e.preventDefault();
                  if (
                    await send({
                      type: "escalate",
                      ticketId: t.id,
                      technicianId: me.id,
                      reason,
                    })
                  )
                    setReason("");
                }}
              >
                <label htmlFor="fl-escalation-reason">
                  Why is senior support needed?
                </label>
                <textarea
                  id="fl-escalation-reason"
                  value={reason}
                  maxLength={1000}
                  rows={3}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="For example: vibration persists; need mechanical lead assessment."
                  required
                />
                <p>
                  The next responder receives your completed checks, notes, and
                  remaining work.
                </p>
                <button
                  className="fl-button fl-primary"
                  disabled={busy || reason.trim().length < 3}
                >
                  Escalate with handoff
                  <ArrowUpRight size={15} />
                </button>
              </form>
            </details>
          </div>
        )}
      </section>
      <aside className="fl-ticket-context">
        <section className="fl-panel">
          <h3>Assignment</h3>
          <dl>
            <div>
              <dt>Equipment</dt>
              <dd>{t.assetId}</dd>
            </div>
            <div>
              <dt>Sector</dt>
              <dd>
                <Link href={`/sectors/${t.sectorId}`}>
                  {t.sectorId}
                  <ArrowUpRight size={12} />
                </Link>
              </dd>
            </div>
            <div>
              <dt>Required skill</dt>
              <dd>{human(t.requiredSkill)}</dd>
            </div>
            <div>
              <dt>Required equipment</dt>
              <dd>{t.requiredEquipment.join(", ") || "Standard kit"}</dd>
            </div>
            <div>
              <dt>Response deadline</dt>
              <dd>{when(t.deadlineAt)}</dd>
            </div>
          </dl>
          <details className="fl-candidates">
            <summary>Why this technician?</summary>
            <p>{t.dispatchReason}</p>
            {t.candidates.map((c) => (
              <div key={c.technicianId}>
                <strong>
                  {state.technicians.find((p) => p.id === c.technicianId)
                    ?.name ?? c.technicianId}
                </strong>
                <span>{c.eligible ? "Eligible" : "Not eligible"}</span>
                <p>{c.reasons.join(" · ")}</p>
              </div>
            ))}
          </details>
        </section>
        <section className="fl-panel">
          <div className="fl-section-head">
            <h3>Work history</h3>
            <span>{logs.length}</span>
          </div>
          {logs
            .filter((a) => a.actorType !== "agent")
            .slice(-8)
            .reverse()
            .map((a) => (
              <ActivityRow entry={a} key={a.id} compact />
            ))}
          {!logs.some((a) => a.actorType !== "agent") && (
            <p className="fl-muted">No technician actions yet.</p>
          )}
        </section>
      </aside>
    </div>
  );
}
function Team({
  state,
  me,
  send,
  busy,
}: {
  state: FleetState;
  me: Technician;
  send: Send;
  busy: boolean;
}) {
  return (
    <>
      <section className="fl-team-settings">
        <div>
          <span className="fl-avatar large">{initials(me.name)}</span>
          <div>
            <h2>{me.name}</h2>
            <p>{me.title}</p>
          </div>
        </div>
        <div className="fl-team-controls">
          <label>
            Checked-in location
            <select
              value={me.checkedInSector}
              disabled={busy}
              onChange={(e) =>
                void send({
                  type: "technician",
                  technicianId: me.id,
                  sectorId: e.target.value as SectorId,
                })
              }
            >
              {state.sectors.map((s) => (
                <option value={s.id} key={s.id}>
                  Sector {s.id} · {s.name}
                </option>
              ))}
            </select>
            <small>Explicit sector check-in, not GPS tracking</small>
          </label>
          <label className="fl-available">
            <input
              type="checkbox"
              checked={me.available}
              disabled={busy}
              onChange={(e) =>
                void send({
                  type: "technician",
                  technicianId: me.id,
                  available: e.target.checked,
                })
              }
            />
            Available for dispatch
          </label>
          <fieldset>
            <legend>Sector subscriptions</legend>
            <div>
              {state.sectors.map((s) => (
                <label key={s.id}>
                  <input
                    type="checkbox"
                    checked={me.subscriptions.includes(s.id)}
                    disabled={busy}
                    onChange={(e) =>
                      void send({
                        type: "technician",
                        technicianId: me.id,
                        subscriptions: e.target.checked
                          ? [...me.subscriptions, s.id]
                          : me.subscriptions.filter((id) => id !== s.id),
                      })
                    }
                  />
                  Sector {s.id}
                </label>
              ))}
            </div>
            <small>Skills, access, and equipment are still required.</small>
          </fieldset>
        </div>
      </section>
      <div className="fl-section-head">
        <h2>On-shift roster</h2>
        <span>
          {state.technicians.filter((t) => t.available).length} available
        </span>
      </div>
      <div className="fl-roster">
        {state.technicians.map((t) => (
          <article key={t.id}>
            <div className="fl-roster-top">
              <span className="fl-avatar">{initials(t.name)}</span>
              <div>
                <h3>{t.name}</h3>
                <p>{t.title}</p>
              </div>
              <span className="fl-badge">
                <span className={`fl-dot ${t.available ? "stable" : ""}`} />
                {t.available ? "Available" : "Unavailable"}
              </span>
            </div>
            <div className="fl-roster-location">
              <MapPin size={14} />
              Sector {t.checkedInSector}
              {t.onCall && <span>On-call escalation</span>}
            </div>
            <dl>
              <div>
                <dt>Skills</dt>
                <dd>{t.skills.map(human).join(" · ")}</dd>
              </div>
              <div>
                <dt>Equipment</dt>
                <dd>{t.equipment.join(", ")}</dd>
              </div>
              <div>
                <dt>Coverage</dt>
                <dd>
                  {t.subscriptions.length
                    ? t.subscriptions.map((id) => `Sector ${id}`).join(", ")
                    : "No subscriptions"}
                </dd>
              </div>
              <div>
                <dt>Access</dt>
                <dd>{t.clearances.join(" · ")}</dd>
              </div>
            </dl>
          </article>
        ))}
      </div>
    </>
  );
}
function ActivityView({ state }: { state: FleetState }) {
  const [sector, setSector] = useState("all"),
    [actor, setActor] = useState("all");
  const list = state.activity
    .filter(
      (a) =>
        (sector === "all" || a.sectorId === sector) &&
        (actor === "all" || a.actorType === actor),
    )
    .slice()
    .reverse();
  return (
    <>
      <div className="fl-activity-toolbar">
        <label>
          Sector
          <select value={sector} onChange={(e) => setSector(e.target.value)}>
            <option value="all">All sectors</option>
            {state.sectors.map((s) => (
              <option key={s.id} value={s.id}>
                Sector {s.id}
              </option>
            ))}
          </select>
        </label>
        <label>
          Performed by
          <select value={actor} onChange={(e) => setActor(e.target.value)}>
            <option value="all">Everyone</option>
            <option value="agent">Agents</option>
            <option value="technician">Technicians</option>
            <option value="system">System</option>
          </select>
        </label>
        <span>{list.length} recorded actions</span>
      </div>
      <div className="fl-full-activity">
        {list.length ? (
          list.map((a) => <ActivityRow entry={a} key={a.id} />)
        ) : (
          <Empty
            title="No activity matches"
            text="Choose another filter or introduce a demo scenario."
          />
        )}
      </div>
    </>
  );
}
function ActivityRow({
  entry: a,
  compact = false,
}: {
  entry: FleetActivity;
  compact?: boolean;
}) {
  return (
    <article className={`fl-activity-row ${compact ? "compact" : ""}`}>
      <span className="fl-activity-icon">
        {a.actorType === "agent" ? (
          <Bot size={15} />
        ) : a.actorType === "technician" ? (
          <Users size={15} />
        ) : (
          <Signal size={15} />
        )}
      </span>
      <div>
        <div className="fl-activity-head">
          <strong>{a.actor}</strong>
          <time>{when(a.ts)}</time>
        </div>
        <p>{a.detail}</p>
        <div className="fl-activity-tags">
          <span>Sector {a.sectorId}</span>
          <span>{human(a.action)}</span>
          {a.mode && <span>{mode(a.mode)}</span>}
          {a.ticketId && (
            <Link href={`/tickets/${a.ticketId}`}>
              {ticketLabel(a.ticketId)}
              <ArrowUpRight size={11} />
            </Link>
          )}
        </div>
        {!compact && a.tool && (
          <details className="fl-payload">
            <summary>
              <Command size={12} />
              {a.tool}
              <span>Inspect tool call</span>
            </summary>
            <div>
              <h4>Input</h4>
              <pre>{JSON.stringify(a.input ?? {}, null, 2)}</pre>
              <h4>Result</h4>
              <pre>{JSON.stringify(a.output ?? {}, null, 2)}</pre>
            </div>
          </details>
        )}
      </div>
    </article>
  );
}
function Empty({ title, text }: { title: string; text: string }) {
  return (
    <div className="fl-empty">
      <ShieldCheck size={25} />
      <h3>{title}</h3>
      <p>{text}</p>
    </div>
  );
}
