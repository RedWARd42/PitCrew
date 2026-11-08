"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Activity,
  ArrowRight,
  ArrowUpRight,
  AudioLines,
  BookOpen,
  Check,
  CheckCheck,
  ChevronRight,
  Clock3,
  FlaskConical,
  Layers3,
  MapPin,
  MessageCircle,
  Mic,
  Moon,
  Play,
  Plus,
  QrCode,
  Radio,
  RotateCcw,
  Route,
  ShieldCheck,
  ShieldAlert,
  Sun,
  Terminal,
  TriangleAlert,
  Wind,
  X,
  Zap,
} from "lucide-react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import QRCode from "qrcode";
import ProcedureCompiler from "./procedure-compiler";
import BrandMark from "./brand-mark";
import DecisionRoom from "./decision-room";
import Investigation from "./investigation";
import {
  TaskHome,
  WorkRounds,
  StartShift,
  GuidedInspection,
  ShiftJourney,
  PresenterHome,
} from "./task-experience";
import {
  StateSchema,
  type PlantState,
  type Asset,
  type Command,
  type Warning,
} from "../../../packages/contracts";

type Sheet = {
  kind: "reading" | "note" | "ack" | "confirm" | "override" | "auth";
  id: string;
};
const nav = [
  { href: "/", label: "Decision room", icon: Activity },
  { href: "/shift", label: "My shift", icon: Layers3 },
  { href: "/rounds", label: "Work rounds", icon: Route },
  { href: "/handover", label: "Handover", icon: CheckCheck },
];
const workspaceNav = [
  { href: "/phone", label: "Team messages", icon: MessageCircle },
  { href: "/topology", label: "Power topology", icon: Layers3 },
  { href: "/tags", label: "Equipment tags", icon: QrCode },
  { href: "/incident", label: "Incident response", icon: Radio },
];
function navActive(href: string, path: string) {
  return href === "/"
    ? path === "/"
    : href === "/rounds"
      ? path.startsWith("/rounds") || path.startsWith("/inspect/")
      : path.startsWith(href);
}
const scenarios = [
  ["S1", "The quiet warning", "Slow chiller drift"],
  ["S2", "Before the breaker", "Maintenance trap"],
  ["S3", "The 2 a.m. cascade", "47 alarms. One incident."],
  ["S4", "Weeks of warning", "Battery impedance creep"],
  ["S5", "Trust, then verify", "A sensor that disagrees"],
] as const;
function time(ts: string) {
  return new Date(ts).toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "America/Chicago",
  });
}
function assetIcon(asset: Asset) {
  return /UPS|PDU|BAT|Row/.test(asset.id) ? Zap : Wind;
}
function diff(asset: Asset) {
  return asset.value - asset.baseline;
}

function Badge({
  children,
  tone = "neutral",
}: {
  children: React.ReactNode;
  tone?: string;
}) {
  return <span className={`badge ${tone}`}>{children}</span>;
}
function Empty({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="empty">
      <ShieldCheck size={30} />
      <h3>{title}</h3>
      <p>{detail}</p>
    </div>
  );
}
function Sparkline({
  values,
  baseline,
  large = false,
}: {
  values: number[];
  baseline: number;
  large?: boolean;
}) {
  const v = values.length > 1 ? values : [baseline, baseline];
  const lo = Math.min(...v, baseline) - 0.15,
    hi = Math.max(...v, baseline) + 0.15;
  const y = (n: number) => 90 - ((n - lo) / (hi - lo)) * 70;
  return (
    <svg
      viewBox="0 0 500 110"
      className={large ? "sparkline large" : "sparkline"}
      role="img"
      aria-label={`Recent readings, latest ${v.at(-1)}, baseline ${baseline}`}
      preserveAspectRatio="none"
    >
      <line
        x1="0"
        x2="500"
        y1={y(baseline)}
        y2={y(baseline)}
        stroke="currentColor"
        strokeDasharray="5 7"
        opacity=".3"
      />
      <path
        d={`M ${v.map((n, i) => `${(i / (v.length - 1)) * 500},${y(n)}`).join(" L ")}`}
        fill="none"
        stroke="var(--mint)"
        strokeWidth={large ? "3" : "2"}
        vectorEffect="non-scaling-stroke"
      />
      <circle cx="498" cy={y(v.at(-1)!)} r="4" fill="var(--mint)" />
    </svg>
  );
}
export default function FieldApp() {
  const pathname = usePathname();
  const [state, setState] = useState<PlantState | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [connected, setConnected] = useState(false);
  const [sheet, setSheet] = useState<Sheet | null>(null);
  const sheetTrigger = useRef<HTMLElement | null>(null);
  const [text, setText] = useState("");
  const [light, setLight] = useState(false);
  const [query, setQuery] = useState("");
  const [listening, setListening] = useState(false);
  const [token] = useState("");
  const [authRequired, setAuthRequired] = useState(false);
  const reduced = useReducedMotion();
  const refresh = useCallback(async () => {
    try {
      const r = await fetch("/api/state");
      if (r.status === 401) {
        setAuthRequired(true);
        throw Error("Enter the server access token to connect.");
      }
      if (!r.ok) throw Error("The plant is taking a moment to respond.");
      setAuthRequired(false);
      setState(StateSchema.parse(await r.json()));
      setError("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Connection unavailable");
    }
  }, []);
  useEffect(() => {
    void refresh();
    const events = new EventSource("/api/events");
    events.onopen = () => setConnected(true);
    events.onerror = () => setConnected(false);
    events.onmessage = (e) => {
      try {
        setState(StateSchema.parse(JSON.parse(e.data)));
      } catch {}
    };
    const poll = setInterval(() => {
      void refresh();
    }, 5000);
    if ("serviceWorker" in navigator)
      void navigator.serviceWorker.register("/sw.js");
    return () => {
      events.close();
      clearInterval(poll);
    };
  }, [refresh]);
  useEffect(() => {
    document.documentElement.dataset.theme = light ? "light" : "dark";
    document
      .querySelector('meta[name="theme-color"]')
      ?.setAttribute("content", light ? "#f8f8ff" : "#080809");
  }, [light]);
  useEffect(() => {
    setQuery("");
    setSheet(null);
  }, [pathname]);
  useEffect(() => {
    if (!notice) return;
    const id = setTimeout(() => setNotice(""), 4500);
    return () => clearTimeout(id);
  }, [notice]);
  useEffect(() => {
    if (!sheet) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setSheet(null);
        return;
      }
      if (event.key !== "Tab") return;
      const controls = Array.from(
        document.querySelectorAll<HTMLElement>(
          '[role="dialog"] button:not(:disabled), [role="dialog"] input:not(:disabled), [role="dialog"] textarea:not(:disabled), [role="dialog"] a[href]',
        ),
      );
      const first = controls[0],
        last = controls.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", onKey);
      sheetTrigger.current?.focus();
    };
  }, [sheet]);
  async function send(command: Command, message = "Saved to this shift") {
    setBusy(true);
    setError("");
    try {
      const r = await fetch("/api/command", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify(command),
      });
      const data = await r.json();
      if (!r.ok) {
        if (r.status === 401) setSheet({ kind: "auth", id: "" });
        throw Error(data.error ?? "Could not save");
      }
      const committed = StateSchema.parse(data);
      setState(committed);
      setNotice(message);
      setSheet(null);
      setText("");
      navigator.vibrate?.(15);
      return committed;
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save");
      return null;
    } finally {
      setBusy(false);
    }
  }
  function open(kind: Sheet["kind"], id: string, value = "") {
    sheetTrigger.current = document.activeElement as HTMLElement | null;
    setText(value);
    setSheet({ kind, id });
  }
  function voice() {
    type SpeechResult = { results: { 0: { 0: { transcript: string } } } };
    type Recognition = {
      lang: string;
      start: () => void;
      onresult: (e: SpeechResult) => void;
      onend: () => void;
      onerror: () => void;
    };
    const speechWindow = window as unknown as {
      SpeechRecognition?: new () => Recognition;
      webkitSpeechRecognition?: new () => Recognition;
    };
    const Ctor =
      speechWindow.SpeechRecognition ?? speechWindow.webkitSpeechRecognition;
    if (!Ctor) {
      setError(
        "Voice input is unavailable in this browser. Type your note below.",
      );
      return;
    }
    const recognition = new Ctor();
    recognition.lang = "en-US";
    recognition.onresult = (e) => setText(e.results[0][0].transcript);
    recognition.onend = () => setListening(false);
    recognition.onerror = () => {
      setListening(false);
      setError("Microphone unavailable. You can type your note.");
    };
    setListening(true);
    recognition.start();
  }
  async function login() {
    try {
      const response = await fetch("/api/auth", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token: text }),
      });
      const result = await response.json();
      if (!response.ok) throw Error(result.error);
      setAuthRequired(false);
      setSheet(null);
      setText("");
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Authentication failed");
    }
  }
  if (!state && authRequired)
    return (
      <div className="loading-screen">
        <BrandMark className="auth-mark" />
        <h2>Connect to your plant.</h2>
        <p>Enter the access token configured for this server.</p>
        <form
          style={{ width: "min(360px,90vw)" }}
          onSubmit={(e) => {
            e.preventDefault();
            void login();
          }}
        >
          <input
            aria-label="Server access token"
            type="password"
            autoComplete="current-password"
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
          <button className="button primary full" type="submit">
            Connect securely
          </button>
        </form>
        {error && <p role="alert">{error}</p>}
      </div>
    );
  if (!state)
    return (
      <div className="loading-screen">
        <BrandMark className="auth-mark" />
        <p>Connecting you to the floor</p>
        {error && (
          <>
            <p role="alert">{error}</p>
            <button onClick={() => void refresh()}>Try again</button>
          </>
        )}
      </div>
    );
  const s = state;
  const active = s.warnings.filter((w) => w.state !== "resolved");
  const degraded = s.assets.some((a) => a.status === "bypass");
  const view = pathname.split("/").filter(Boolean);
  const asset =
    view[0] === "a"
      ? s.assets.find((a) => a.id === decodeURIComponent(view[1] ?? ""))
      : undefined;
  const warning =
    view[0] === "warnings"
      ? s.warnings.find((w) => w.id === view[1])
      : undefined;
  const EquipmentIcon = asset ? assetIcon(asset) : Wind;
  const person = (id: string) => s.people.find((p) => p.id === id)?.name ?? id;
  const pageInfo: Record<string, { title: string; description: string }> = {
    investigate: {title: "Investigation", description: ""},
    shift: {
      title: "My shift",
      description:
        "Pick up the context, follow your next job, and leave a clear handover.",
    },
    start: {
      title: "Start my shift",
      description:
        "Receive the handover. Read back the commitments you are taking onto the floor.",
    },
    inspect: {
      title: "Equipment inspection",
      description:
        "Review the evidence, record what you find, and close the ownership loop.",
    },
    presenter: {
      title: "Presenter workspace",
      description:
        "Scenario controls and decision traces for the demonstration.",
    },
    rounds: {
      title: "Work my rounds",
      description:
        "Your route, ordered by risk. Start with the equipment that needs you most.",
    },
    assets: {
      title: "Equipment",
      description:
        "Live readings, field observations, and the context behind every asset.",
    },
    handover: {
      title: "Hand over my shift",
      description:
        "A shared record of what happened, what comes next, and who owns it.",
    },
    procedures: {
      title: "Procedures",
      description:
        "Approved instructions. Live preconditions. Every step accounted for.",
    },
    _director: {
      title: "Demo Director",
      description:
        "Load a scenario, control the clock, and follow every decision.",
    },
    traces: {
      title: "Decision traces",
      description:
        "The evidence, tool calls, and reasoning behind each recommendation.",
    },
    phone: {
      title: "Message mirror",
      description:
        "One conversation across the floor, on-call team, and incoming shift.",
    },
    topology: {
      title: "Power topology",
      description: "Follow the protected feeds from source to load.",
    },
    tags: {
      title: "Equipment tags",
      description:
        "A direct link from the physical floor to its digital record.",
    },
    incident: {
      title: "Incident response",
      description:
        "A shared picture of the event, the response, and the time available.",
    },
    warnings: {
      title: "Open warnings",
      description: "Evidence, ownership, and the next action in one place.",
    },
  };
  const title =
    asset?.name ??
    (warning ? "Warning details" : undefined) ??
    pageInfo[view[0]]?.title ??
    "Decision room";
  function warningCard(w: Warning) {
    const a = s.assets.find((a) => a.id === w.assetId);
    const left = Math.round(
      (new Date(w.dueAt).getTime() - new Date(s.clock).getTime()) / 60000,
    );
    return (
      <Link href={`/warnings/${w.id}`} className="warning-row" key={w.id}>
        <div className={`severity-icon ${w.severity}`}>
          <TriangleAlert size={20} />
        </div>
        <div className="grow">
          <div className="row-between">
            <span className="micro">{a?.name ?? w.assetId}</span>
            <Badge tone={w.severity}>
              {w.state === "owned"
                ? "Owned"
                : w.severity === "critical"
                  ? "Critical"
                  : "Needs attention"}
            </Badge>
          </div>
          <h3>{w.title}</h3>
          <p>
            {person(w.ownerId)} <span className="dot">·</span>{" "}
            {left > 0 ? `${left} min left` : "Due now"}
          </p>
        </div>
        <ChevronRight size={18} />
      </Link>
    );
  }
  function assetCard(a: Asset, i?: number) {
    const Icon = assetIcon(a);
    const delta = diff(a);
    return (
      <Link href={`/a/${a.id}`} className="asset-row" key={a.id}>
        {i !== undefined ? (
          <span className="stop-number">{String(i + 1).padStart(2, "0")}</span>
        ) : null}
        <div
          className={`asset-icon ${Math.abs(delta) > 0.4 ? "attention" : ""}`}
        >
          <Icon size={23} />
        </div>
        <div className="grow">
          <div className="row-between">
            <h3>{a.name}</h3>
          </div>
          <p>
            {i === 0 && Math.abs(delta) > 0.4
              ? "Drift + open note · check this first"
              : `${a.zone} · ${a.status}`}
          </p>
        </div>
        <div className="asset-reading">
          <span className="reading-small">
            {a.value.toFixed(1)}
            <small>{a.unit}</small>
          </span>
          <span className="micro">{a.id}</span>
        </div>
        <ChevronRight size={18} />
      </Link>
    );
  }
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <Link href="/" className="wordmark">
          <BrandMark />
          PitCrew
        </Link>
        <div className="site-selector">
          <span className="site-emblem">
            <Layers3 size={19} />
          </span>
          <div>
            <strong>NMC² DAL-1</strong>
            <small>Hall 2 · Dallas, TX</small>
          </div>
          <ChevronRight size={15} />
        </div>
        <span className="nav-caption">ON THE FLOOR</span>
        <nav>
          {[
            ...nav,
            { href: "/assets", label: "Equipment", icon: QrCode },
            { href: "/procedures", label: "Procedures", icon: BookOpen },
          ].map((n) => (
            <Link
              key={n.href}
              className={navActive(n.href, pathname) ? "selected" : ""}
              href={n.href}
              aria-current={navActive(n.href, pathname) ? "page" : undefined}
            >
              {navActive(n.href, pathname) && (
                <motion.span
                  className="nav-indicator"
                  layoutId="desktop-active"
                  transition={{
                    duration: reduced ? 0 : 0.18,
                    ease: [0.23, 1, 0.32, 1],
                  }}
                />
              )}
              <n.icon size={20} />
              {n.label}
              {n.href === "/handover" &&
                s.handover.filter((i) => !i.confirmed).length > 0 && (
                  <span className="nav-count">
                    {s.handover.filter((i) => !i.confirmed).length}
                  </span>
                )}
            </Link>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <span className="nav-caption">WORKSPACE</span>
          {workspaceNav.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={pathname === item.href ? "selected" : ""}
              aria-current={pathname === item.href ? "page" : undefined}
            >
              <item.icon size={18} />
              {item.label}
            </Link>
          ))}
          <div className="profile">
            <div className="avatar">M</div>
            <div>
              <strong>Maria Santos</strong>
              <small>Floor technician</small>
            </div>
            <button
              className="icon-button"
              aria-label="Toggle light mode"
              onClick={() => setLight(!light)}
            >
              {light ? <Moon size={18} /> : <Sun size={18} />}
            </button>
          </div>
        </div>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <div className="breadcrumb">
            <span>DAL-1</span>
            <ChevronRight size={13} />
            <strong>Hall 2</strong>
          </div>
          <div className="topbar-right">
            {["presenter", "_director", "traces"].includes(view[0]) && (
              <Link href="/presenter" className="director-shortcut">
                <FlaskConical size={16} />
                <span>Presenter workspace</span>
              </Link>
            )}
            <Link
              href="/topology"
              className={`redundancy ${degraded ? "degraded" : ""}`}
            >
              <span className="status-dot" />
              <span>Power</span>
              <strong>{degraded ? "N · degraded" : "N+1"}</strong>
              <ChevronRight size={13} />
            </Link>
            <span className="clock">
              <Clock3 size={14} />
              {time(s.clock)}
            </span>
            <button
              onClick={() => setLight(!light)}
              className="icon-button mobile-theme"
              aria-label="Toggle light mode"
            >
              {light ? <Moon size={18} /> : <Sun size={18} />}
            </button>
          </div>
        </header>
        <motion.main
          key={pathname}
          data-view={view[0] ?? "shift"}
          initial={{
            opacity: 0,
            transform: reduced ? "none" : "translateY(6px)",
          }}
          animate={{ opacity: 1, transform: "translateY(0px)" }}
          transition={{
            duration: reduced ? 0.01 : 0.18,
            ease: [0.23, 1, 0.32, 1],
          }}
        >
          <div className="page-heading">
            <div>
              <h1>{title}</h1>
            </div>
            {view[0] === "_director" ? (
              <button
                className="button secondary reset-action"
                disabled={busy}
                onClick={() =>
                  void send({ type: "reset" }, "Seed site restored")
                }
              >
                <RotateCcw size={16} />
                Reset demo
              </button>
            ) : (
              <div className="live-indicator">
                <span
                  className={connected ? "status-dot" : "status-dot amber"}
                />
                {connected ? "Plant connected" : "Reconnecting"}
                <small>SEEDED DEMO</small>
              </div>
            )}
          </div>
          <nav className="mobile-workspace" aria-label="Field reference pages">
            {[
              { href: "/assets", label: "Equipment" },
              { href: "/procedures", label: "Procedures" },
              { href: "/phone", label: "Team messages" },
              { href: "/tags", label: "Tags" },
            ].map((item) => (
              <Link
                href={item.href}
                key={item.href}
                aria-current={pathname === item.href ? "page" : undefined}
              >
                {item.label}
              </Link>
            ))}
          </nav>
          {["presenter", "_director", "traces"].includes(view[0]) && (
            <nav className="presenter-links" aria-label="Presenter tools">
              <Link className="button secondary" href="/presenter">
                Presenter workspace
              </Link>
              <Link className="button secondary" href="/_director">
                Scenario Director
              </Link>
              <Link className="button secondary" href="/traces">
                Decision traces
              </Link>
              <Link className="button secondary" href="/">
                Back to the floor
              </Link>
            </nav>
          )}
          {error && (
            <div role="alert" className="alert">
              <TriangleAlert size={18} />
              {error}
              <button aria-label="Dismiss error" onClick={() => setError("")}>
                <X size={16} />
              </button>
            </div>
          )}
          {view.length === 0 && <DecisionRoom state={s} />}
          {view[0] === "shift" && <TaskHome state={s} />}
          {view[0] === "investigate" && <Investigation key={view[1]} state={s} assetId={decodeURIComponent(view[1] ?? "")} send={send} busy={busy} />}
          {view[0] === "start" && <StartShift state={s} open={open} />}
          {view[0] === "rounds" && <WorkRounds state={s} />}
          {view[0] === "inspect" && (
            <GuidedInspection
              key={view[1]}
              assetId={decodeURIComponent(view[1] ?? "")}
              state={s}
              send={send}
              busy={busy}
            />
          )}
          {view[0] === "presenter" && <PresenterHome />}
          {view[0] === "assets" && (
            <>
              <div className="toolbar">
                <label className="search">
                  <QrCode size={18} />
                  <input
                    aria-label="Find equipment"
                    placeholder="Find equipment by name or tag…"
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                  />
                </label>
                <Link href="/tags" className="button secondary">
                  <QrCode size={18} />
                  Tag wall
                </Link>
              </div>
              <section className="card equipment-list">
                <div className="list-heading">
                  <span>Equipment</span>
                  <span>Reading / tag</span>
                </div>
                {s.assets
                  .filter((a) =>
                    `${a.name} ${a.id}`
                      .toLowerCase()
                      .includes(query.toLowerCase()),
                  )
                  .map((a) => assetCard(a))}
                {!s.assets.some((a) =>
                  `${a.name} ${a.id}`
                    .toLowerCase()
                    .includes(query.toLowerCase()),
                ) && (
                  <Empty
                    title="No matching equipment"
                    detail="Try an asset name or tag, or clear the search."
                  />
                )}
              </section>
            </>
          )}
          {view[0] === "a" && !asset && (
            <Empty
              title="Asset not found"
              detail="Choose equipment from the Equipment tab."
            />
          )}
          {asset && (
            <div className="asset-layout">
              <div className="main-column">
                <section className="asset-pass">
                  <div className="row-between">
                    <span className="micro">PITCREW / EQUIPMENT PASS</span>
                    <QrCode size={24} />
                  </div>
                  <div className="asset-title">
                    <div className="asset-icon large">
                      <EquipmentIcon size={35} />
                    </div>
                    <div>
                      <span className="micro">{asset.id}</span>
                      <h2>{asset.name}</h2>
                      <p>
                        <MapPin size={14} />
                        {asset.zone}
                      </p>
                    </div>
                    <Badge tone={asset.status === "bypass" ? "watch" : "mint"}>
                      {asset.status}
                    </Badge>
                  </div>
                  <div className="pass-bottom">
                    <span>CONNECTED TO THE FLOOR</span>
                    <span>{asset.feeds.length} upstream sources</span>
                  </div>
                </section>
                <section className="card metric-card">
                  <div className="row-between">
                    <h3>{asset.metric}</h3>
                    <Badge>5-day view</Badge>
                  </div>
                  <div className="metric-value">
                    {asset.value.toFixed(1)}
                    <span>{asset.unit}</span>
                  </div>
                  <p
                    className={Math.abs(diff(asset)) > 0.4 ? "amber-text" : ""}
                  >
                    {diff(asset) >= 0 ? "↑" : "↓"}{" "}
                    {Math.abs(diff(asset)).toFixed(1)}
                    {asset.unit} vs your baseline of {asset.baseline.toFixed(1)}
                    {asset.unit}
                  </p>
                  <Sparkline
                    values={asset.history}
                    baseline={asset.baseline}
                    large
                  />
                  <div className="row-between micro">
                    <span>5 DAYS AGO</span>
                    <span>NOW</span>
                  </div>
                  <button
                    className="button primary full"
                    onClick={() =>
                      open("reading", asset.id, String(asset.value))
                    }
                  >
                    <Plus size={18} />
                    Log a reading
                  </button>
                </section>
                <div className="section-heading">
                  <h2>Pinned field notes</h2>
                  <button onClick={() => open("note", asset.id)}>
                    <Plus size={17} /> Add note
                  </button>
                </div>
                <section className="card notes">
                  {s.notes
                    .filter((n) => n.assetId === asset.id)
                    .map((n) => (
                      <article key={n.id}>
                        <div className="row-between">
                          <div className="note-author">
                            <span className="avatar small">{n.author[0]}</span>
                            <strong>{n.author}</strong>
                          </div>
                          <span className="micro">{time(n.ts)}</span>
                        </div>
                        <p>{n.text}</p>
                        <Badge tone={n.structured.severity}>
                          {n.structured.component} ·{" "}
                          {n.structured.followUp
                            ? "Follow-up needed"
                            : "Logged"}
                        </Badge>
                      </article>
                    ))}
                  {!s.notes.some((n) => n.assetId === asset.id) && (
                    <Empty
                      title="A fresh page for this asset"
                      detail="Pin anything the next technician should know."
                    />
                  )}
                </section>
                <div className="section-heading">
                  <h2>Recent shift history</h2>
                </div>
                <section className="card">
                  {["Current shift", "Previous shift", "Two shifts ago"].map(
                    (label, i) => (
                      <div className="history-row" key={label}>
                        <Clock3 size={17} />
                        <div>
                          <strong>{label}</strong>
                          <p>
                            {i === 0
                              ? "Live readings and field notes attached"
                              : `Seed reference: ${asset.baseline.toFixed(1)}${asset.unit} · historical shift log not connected`}
                          </p>
                        </div>
                      </div>
                    ),
                  )}
                </section>
              </div>
              <aside className="context-column">
                <div className="section-heading first">
                  <h2>Open warnings</h2>
                </div>
                <section className="card">
                  {active
                    .filter((w) => w.assetId === asset.id)
                    .map(warningCard)}
                  {!active.some((w) => w.assetId === asset.id) && (
                    <Empty
                      title="No open warnings"
                      detail="We’ll surface changes here."
                    />
                  )}
                </section>
                <div className="section-heading">
                  <h2>Related procedures</h2>
                </div>
                <section className="card">
                  {s.procedures
                    .filter(
                      (p) =>
                        p.assetTypes.includes(asset.type) ||
                        p.title.includes(asset.id) ||
                        p.assetTypes.includes("all"),
                    )
                    .map((p) => (
                      <Link
                        key={p.id}
                        className="procedure-link"
                        href={`/procedures?procedure=${p.id}&asset=${asset.id}`}
                      >
                        <BookOpen size={20} />
                        <div>
                          <strong>{p.title}</strong>
                          <p>
                            Rev {p.version} ·{" "}
                            {p.approved ? "Approved" : "Review required"}
                          </p>
                        </div>
                        <ChevronRight size={16} />
                      </Link>
                    ))}
                  <Link
                    href={`/procedures?asset=${asset.id}`}
                    className="text-link"
                  >
                    Browse procedures <ArrowRight size={15} />
                  </Link>
                </section>
                <Link className="redundancy-note" href="/topology">
                  <Layers3 size={22} />
                  <div>
                    <strong>
                      {degraded ? "Single-feed context" : "Redundancy intact"}
                    </strong>
                    <p>
                      {degraded
                        ? "UPS-2 in bypass. Check every isolation."
                        : "See upstream power and cooling sources."}
                    </p>
                  </div>
                  <ChevronRight size={17} />
                </Link>
              </aside>
            </div>
          )}
          {warning && (
            <div className="warning-workspace detail-narrow">
              <section className="card warning-detail">
                <div className="row-between">
                  <Badge tone={warning.severity}>
                    <TriangleAlert size={14} />
                    {warning.severity}
                  </Badge>
                  <span className="micro">{warning.id}</span>
                </div>
                <h2>{warning.title}</h2>
                <Link href={`/a/${warning.assetId}`} className="text-link">
                  {warning.assetId}
                  <ArrowUpRight size={15} />
                </Link>
                <div className="ownership">
                  <div className="avatar">{person(warning.ownerId)[0]}</div>
                  <div>
                    <span className="micro">ACCOUNTABLE OWNER</span>
                    <h3>{person(warning.ownerId)}</h3>
                  </div>
                  <div className="due">
                    <Clock3 size={18} />
                    <strong>{time(warning.dueAt)}</strong>
                    <small>Due this shift</small>
                  </div>
                </div>
                <p>{warning.nextAction}</p>
                {warning.readback ? (
                  <blockquote>
                    “{warning.readback}”
                    <small>
                      Read-back confirmed · {person(warning.ownerId)}
                    </small>
                  </blockquote>
                ) : (
                  <button
                    className="button primary full"
                    onClick={() => open("ack", warning.id)}
                  >
                    <CheckCheck size={18} />
                    Own it with a read-back
                  </button>
                )}
              </section>
              <aside className="warning-context">
                <div className="section-heading">
                  <h2>The evidence</h2>
                  <Link href="/traces">
                    See decision <ArrowUpRight size={15} />
                  </Link>
                </div>
                <section className="card evidence">
                  {warning.evidence.map((e, i) => (
                    <div key={i}>
                      <Check size={17} />
                      <p>{e}</p>
                    </div>
                  ))}
                </section>
                <div className="section-heading">
                  <h2>Escalation, with accountability</h2>
                </div>
                <section className="card ladder">
                  {[
                    "Owner notified",
                    "Read, awaiting acknowledgement",
                    "On-call engineer + voice",
                  ].map((text, i) => (
                    <div
                      className={warning.escalationLevel >= i ? "done" : ""}
                      key={text}
                    >
                      <span>
                        {warning.state === "owned" ? (
                          <Check size={14} />
                        ) : (
                          i + 1
                        )}
                      </span>
                      <div>
                        <strong>{text}</strong>
                        <p>
                          {i === 0
                            ? "At the floor"
                            : i === 1
                              ? "20 seconds without a read-back"
                              : "45 seconds without ownership"}
                        </p>
                      </div>
                    </div>
                  ))}
                </section>
                <Link href="/phone" className="button secondary full">
                  <MessageCircle size={18} />
                  Open message mirror
                </Link>
              </aside>
            </div>
          )}
          {view[0] === "warnings" && !warning && (
            <section className="card">{active.map(warningCard)}</section>
          )}
          {view[0] === "handover" && (
            <>
              <ShiftJourney state={s} current="handover" />
              <div className="field-summary">
                <CheckCheck size={19} />
                <p>
                  Draft from this shift to gather the observations and ongoing
                  commitments you need to pass on. Incoming-shift read-backs
                  remain visible on every item.
                </p>
              </div>
              <div className="toolbar">
                <span className="micro">I-PASS · ORDERED BY WALKING ROUTE</span>
                <button
                  className="button secondary"
                  disabled={busy}
                  onClick={() =>
                    void send(
                      { type: "handover" },
                      "Handover drafted from the current shift",
                    )
                  }
                >
                  <Activity size={18} />
                  Draft from this shift
                </button>
              </div>
              <div
                className="handover-progress"
                role="progressbar"
                aria-label="Handover confirmations"
                aria-valuemin={0}
                aria-valuemax={s.handover.length || 1}
                aria-valuenow={
                  s.handover.filter((item) => item.confirmed).length
                }
              >
                <motion.span
                  initial={false}
                  animate={{
                    transform: `scaleX(${s.handover.filter((item) => item.confirmed).length / Math.max(1, s.handover.length)})`,
                  }}
                  transition={{
                    duration: reduced ? 0 : 0.2,
                    ease: [0.23, 1, 0.32, 1],
                  }}
                />
              </div>
              <div className="handover-list">
                {s.handover.map((item, i) => (
                  <motion.article
                    layout={!reduced}
                    transition={{ duration: 0.2, ease: [0.23, 1, 0.32, 1] }}
                    key={item.id}
                    className={`card handover-item ${item.confirmed ? "confirmed" : ""}`}
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
                        <Badge tone={item.severity}>
                          {item.confirmed ? "Confirmed" : item.severity}
                        </Badge>
                      </div>
                      <h2>{item.summary}</h2>
                      <div className="ipass">
                        <p>
                          <span>ACTION</span>
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
                          className="button secondary"
                          onClick={() => open("confirm", item.id)}
                        >
                          <CheckCheck size={18} />
                          Confirm with a read-back
                        </button>
                      )}
                    </div>
                  </motion.article>
                ))}
                {!s.handover.length && (
                  <Empty
                    title="Ready for a good handoff"
                    detail="Draft the handover to gather warnings, notes, and maintenance context."
                  />
                )}
              </div>
              <div className="handover-send">
                <div>
                  <h3>
                    {s.handover.filter((i) => i.confirmed).length} of{" "}
                    {s.handover.length} confirmed
                  </h3>
                  <p>
                    Unconfirmed critical items stay highlighted for the next
                    shift.
                  </p>
                </div>
                <button
                  disabled={busy || !s.handover.length}
                  className="button primary"
                  onClick={() =>
                    void send(
                      { type: "send_handover" },
                      "Handover sent to the incoming shift",
                    )
                  }
                >
                  <MessageCircle size={18} />
                  Send to incoming shift
                </button>
              </div>
            </>
          )}
          {view[0] === "procedures" && (
            <ProcedureView state={s} busy={busy} send={send} open={open} />
          )}
          {view[0] === "incident" &&
            (s.incidents.length ? (
              s.incidents.map((incident) => (
                <div
                  className="incident-workspace detail-narrow"
                  key={incident.id}
                >
                  <section className="card incident-card">
                    <Badge tone="critical">
                      <Radio size={14} /> ACTIVE INCIDENT · {incident.id}
                    </Badge>
                    <div className="countdown-ring">
                      <span>
                        ≈{incident.etaMinutes?.toFixed(0) ?? "—"}
                        <small>MIN TO RESTART LIMIT</small>
                      </span>
                    </div>
                    <h2>{incident.title}</h2>
                    <p>{incident.hypothesis}</p>
                    <div className="correlation">
                      <span>
                        {incident.alarmCount}
                        <small>RAW ALARMS</small>
                      </span>
                      <ArrowRight />
                      <span>
                        1<small>SHARED RESPONSE</small>
                      </span>
                    </div>
                    <p className="micro">
                      CONFIDENCE BAND{" "}
                      {incident.confidence
                        ?.map((n) => n.toFixed(0))
                        .join("–") ?? "Unavailable"}{" "}
                      MINUTES
                    </p>
                    <details>
                      <summary>Projection assumptions</summary>
                      {incident.assumptions.map((a) => (
                        <p key={a}>{a}</p>
                      ))}
                    </details>
                    <Link
                      href={`/procedures?procedure=${incident.procedureId}&asset=CH-3`}
                      className="button primary full"
                    >
                      <BookOpen size={18} />
                      Open emergency procedure
                    </Link>
                  </section>
                  <aside className="incident-context">
                    <div className="section-heading">
                      <h2>People in the loop</h2>
                    </div>
                    <section className="card">
                      {s.messages
                        .filter((m) => m.entityId === incident.id)
                        .map((m) => (
                          <div className="contact-row" key={m.id}>
                            <div className="avatar">
                              {person(m.personId)[0]}
                            </div>
                            <div className="grow">
                              <h3>{person(m.personId)}</h3>
                              <p>
                                {m.channel} · {m.status}
                              </p>
                            </div>
                            <CheckCheck size={19} />
                          </div>
                        ))}
                    </section>
                    <Link href="/phone" className="text-link">
                      Open the incident conversation <ArrowRight size={16} />
                    </Link>
                  </aside>
                </div>
              ))
            ) : (
              <Empty
                title="No active incident"
                detail="When alarms share a cause, one focused response appears here."
              />
            ))}
          {view[0] === "_director" && (
            <>
              <div className="director-status">
                <Badge tone="mint">DETERMINISTIC DEMO</Badge>
                <span>
                  {s.scenario ?? "Seed site"} ·{" "}
                  {s.paused ? "Paused" : "Running"} · {s.cacheMode} cache
                </span>
                <span>{s.clock}</span>
              </div>
              <section className="card director-controls">
                <h3>The clock</h3>
                <div className="button-row">
                  <button
                    className="button secondary"
                    onClick={() =>
                      void send(
                        { type: "pause", paused: !s.paused },
                        s.paused ? "Clock resumed" : "Clock paused",
                      )
                    }
                  >
                    {s.paused ? "Resume" : "Pause"}
                  </button>
                  {[20, 45, 60, 3600].map((seconds) => (
                    <button
                      className="button secondary"
                      disabled={busy}
                      key={seconds}
                      onClick={() =>
                        void send({ type: "step", seconds }, "Clock advanced")
                      }
                    >
                      +{seconds >= 3600 ? "1 hour" : `${seconds} sec`}
                    </button>
                  ))}
                </div>
                <div className="button-row">
                  <span className="micro">AGENT CACHE</span>
                  {(["only", "prefer", "live"] as const).map((mode) => (
                    <button
                      className={`button ${s.cacheMode === mode ? "primary" : "secondary"}`}
                      disabled={busy}
                      onClick={() =>
                        void send({ type: "cache", mode }, `Cache: ${mode}`)
                      }
                      key={mode}
                    >
                      {mode}
                    </button>
                  ))}
                </div>
                <div className="button-row">
                  <Link className="button secondary" href="/traces">
                    <Activity size={18} />
                    Traces
                  </Link>
                  <Link className="button secondary" href="/phone">
                    <MessageCircle size={18} />
                    Phone mirror
                  </Link>
                  <Link className="button secondary" href="/tags">
                    <QrCode size={18} />
                    QR tag wall
                  </Link>
                </div>
              </section>
              <div className="section-heading">
                <h2>Scenarios</h2>
                <span className="micro">{scenarios.length} SEEDED STORIES</span>
              </div>
              <div className="scenario-grid">
                {scenarios.map(([id, title, detail]) => (
                  <button
                    className={`card scenario-card ${s.scenario === id ? "active" : ""}`}
                    key={id}
                    disabled={busy}
                    onClick={() =>
                      void send({ type: "scenario", id }, `${id} loaded`)
                    }
                  >
                    <div className="row-between">
                      <span className="scenario-id">{id}</span>
                      <Play size={19} />
                    </div>
                    <h2>{title}</h2>
                    <p>{detail}</p>
                  </button>
                ))}
              </div>

              <div className="section-heading">
                <h2>Audit trail</h2>
                <span className="micro">{s.audit.length} EVENTS</span>
              </div>
              <section className="card audit-list">
                {s.audit
                  .slice(-30)
                  .reverse()
                  .map((a) => (
                    <div key={a.id}>
                      <span className="micro">{time(a.ts)}</span>
                      <strong>{a.action}</strong>
                      <p>{a.detail}</p>
                    </div>
                  ))}
              </section>
            </>
          )}
          {view[0] === "traces" && (
            <div className="traces">
              <div className="trace-overview">
                <span className="micro">DECISION LOG</span>
                <span>{s.traces.length} recorded decisions</span>
              </div>
              {s.traces
                .slice()
                .reverse()
                .map((trace) => (
                  <article className="card trace" key={trace.id}>
                    <div className="row-between">
                      <Badge tone={trace.mode === "live" ? "mint" : "neutral"}>
                        {trace.mode.toUpperCase()}
                      </Badge>
                      <span className="micro">
                        {trace.latencyMs} MS · {time(trace.ts)}
                      </span>
                    </div>
                    <h2>{trace.agent}</h2>
                    <p>{trace.summary}</p>
                    <div className="trace-model">
                      {trace.model} · Trigger: {trace.trigger}
                    </div>
                    <div className="trace-plan">
                      {trace.plan.map((step, i) => (
                        <div key={i}>
                          <span>
                            <Check size={13} />
                          </span>
                          {step}
                        </div>
                      ))}
                    </div>
                    <div className="tool-calls">
                      {trace.steps.map((step, i) => (
                        <details key={i}>
                          <summary>
                            <span>
                              <Terminal size={15} />
                              {step.tool}
                            </span>
                            <span>
                              {step.latencyMs} ms <ChevronRight size={14} />
                            </span>
                          </summary>
                          <p>{step.summary}</p>
                          <div className="trace-data">
                            <div>
                              <span className="micro">INPUT</span>
                              <pre>{JSON.stringify(step.input, null, 2)}</pre>
                            </div>
                            <div>
                              <span className="micro">RESULT</span>
                              <pre>{JSON.stringify(step.result, null, 2)}</pre>
                            </div>
                          </div>
                        </details>
                      ))}
                    </div>
                  </article>
                ))}
              {!s.traces.length && (
                <Empty
                  title="The next decision starts a trail"
                  detail="Start a scenario in the Demo Director to inspect tool calls and evidence."
                />
              )}
            </div>
          )}
          {view[0] === "phone" && (
            <div className="phone-layout">
              <div className="phone-frame">
                <div className="phone-top">
                  <span>MESSAGE ACTIVITY</span>
                  <AudioLines size={15} />
                </div>
                <div className="phone-contact">
                  <div className="avatar brand-avatar">
                    <BrandMark />
                  </div>
                  <strong>PitCrew</strong>
                  <small>Plant operations · message mirror</small>
                </div>
                <div className="phone-messages">
                  {s.messages.map((m) => (
                    <div className={`message ${m.direction}`} key={m.id}>
                      <span className="micro">
                        {person(m.personId)} · {m.channel}
                      </span>
                      <p>{m.text}</p>
                      <small>
                        {time(m.ts)} · {m.status}
                      </small>
                      {m.direction === "outbound" && (
                        <button
                          onClick={() =>
                            void send(
                              { type: "read", messageId: m.id },
                              "Message marked read",
                            )
                          }
                        >
                          Mark read <CheckCheck size={13} />
                        </button>
                      )}
                      {s.warnings.find(
                        (w) => w.id === m.entityId && w.state !== "owned",
                      ) && (
                        <button onClick={() => open("ack", m.entityId)}>
                          Reply with ownership <ArrowUpRight size={13} />
                        </button>
                      )}
                    </div>
                  ))}
                  {!s.messages.length && (
                    <p className="caption">
                      Messages appear here as warnings are created.
                    </p>
                  )}
                </div>
                <div className="phone-bottom">
                  Encrypted transport depends on the selected provider
                </div>
              </div>
              <div className="phone-explainer">
                <Badge tone="mint">
                  <MessageCircle size={13} /> COMMS FALLBACK
                </Badge>
                <h2>
                  Same message.
                  <br />
                  Everyone included.
                </h2>
                <p>
                  Ownership travels beyond the floor. This mirror keeps the demo
                  working when a phone or provider is unavailable.
                </p>
                <p>
                  Messages labeled terminal or simulated have not been delivered
                  to a real phone.
                </p>
                <Link href="/warnings" className="text-link">
                  Review open commitments <ArrowRight size={16} />
                </Link>
              </div>
            </div>
          )}
          {view[0] === "topology" && (
            <div className="topology-workspace detail-narrow">
              <section className="card topology">
                <Badge tone={degraded ? "watch" : "mint"}>
                  {degraded
                    ? "N · REDUNDANCY REDUCED"
                    : "N+1 · REDUNDANCY INTACT"}
                </Badge>
                <h2>Two sources. One shared responsibility.</h2>
                <p>
                  Opening an isolation is checked against the live source graph
                  before a step can proceed.
                </p>
                <div className="topology-sources">
                  {s.assets
                    .filter((a) => a.id.startsWith("UPS"))
                    .map((a) => (
                      <Link
                        href={`/a/${a.id}`}
                        className={
                          a.status === "bypass" ? "source degraded" : "source"
                        }
                        key={a.id}
                      >
                        <Zap />
                        <h3>{a.id}</h3>
                        <Badge tone={a.status === "bypass" ? "watch" : "mint"}>
                          {a.status}
                        </Badge>
                      </Link>
                    ))}
                </div>
                <div className="topology-lines">
                  ↓<span>INDEPENDENT FEEDS</span>↓
                </div>
                <Link href="/a/Row-D" className="topology-load">
                  <Layers3 />
                  <strong>Row D · AI load</strong>
                  <span>
                    {degraded
                      ? "Single available protected feed"
                      : "Dual protected feeds"}
                  </span>
                </Link>
                <div className="caption">
                  Advisory simulation only. PitCrew never operates plant
                  controls.
                </div>
              </section>
            </div>
          )}
          {view[0] === "tags" && (
            <>
              <div className="toolbar">
                <p>
                  Scan on a second screen, or print the tags. URLs use this
                  device’s current host.
                </p>
                <button
                  className="button secondary"
                  onClick={() => window.print()}
                >
                  Print tags
                </button>
              </div>
              <div className="tag-grid">
                {s.assets.map((a) => (
                  <TagCard key={a.id} asset={a} />
                ))}
              </div>
            </>
          )}
          <footer className="page-footer">
            <span>
              <BrandMark className="footer-mark" />
              At the equipment. Ahead of the next shift.
            </span>
            <span>
              ADVISORY ONLY <span className="dot">·</span> DAL-1 / HALL 2
            </span>
          </footer>
        </motion.main>
      </div>
      <nav className="mobile-nav">
        {nav.map((n) => (
          <Link
            href={n.href}
            aria-current={navActive(n.href, pathname) ? "page" : undefined}
            key={n.href}
            className={navActive(n.href, pathname) ? "selected" : ""}
          >
            <n.icon size={20} />
            <span>{n.label === "Work rounds" ? "My rounds" : n.label}</span>
          </Link>
        ))}
      </nav>
      <AnimatePresence>
        {notice && (
          <motion.div
            key="notice"
            role="status"
            className="toast"
            initial={{
              opacity: 0,
              transform: reduced
                ? "translateX(-50%)"
                : "translateX(-50%) translateY(8px)",
            }}
            animate={{
              opacity: 1,
              transform: "translateX(-50%) translateY(0px)",
            }}
            exit={{
              opacity: 0,
              transform: reduced
                ? "translateX(-50%)"
                : "translateX(-50%) translateY(8px)",
            }}
            transition={{
              duration: reduced ? 0.01 : 0.2,
              ease: [0.23, 1, 0.32, 1],
            }}
          >
            <Check size={18} />
            {notice}
          </motion.div>
        )}
      </AnimatePresence>
      <AnimatePresence>
        {sheet && (
          <motion.div
            key="sheet-backdrop"
            className="sheet-backdrop"
            onClick={() => setSheet(null)}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: reduced ? 0.01 : 0.2 }}
          >
            <motion.section
              key={sheet.kind + sheet.id}
              initial={{
                opacity: 0,
                transform: reduced ? "none" : "translateY(16px) scale(0.98)",
              }}
              animate={{ opacity: 1, transform: "translateY(0px) scale(1)" }}
              exit={{
                opacity: 0,
                transform: reduced ? "none" : "translateY(16px) scale(0.98)",
              }}
              transition={{
                duration: reduced ? 0.01 : 0.25,
                ease: [0.23, 1, 0.32, 1],
              }}
              role="dialog"
              aria-modal="true"
              aria-labelledby="sheet-title"
              className="sheet"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="sheet-handle" />
              <div className="row-between">
                <span className="eyebrow">
                  {sheet.kind === "reading"
                    ? "ROUND READING"
                    : sheet.kind === "note"
                      ? "FIELD SCRIBE"
                      : sheet.kind === "auth"
                        ? "SERVER ACCESS"
                        : "CLOSED-LOOP CONFIRMATION"}
                </span>
                <button
                  className="icon-button"
                  aria-label="Close dialog"
                  onClick={() => setSheet(null)}
                >
                  <X />
                </button>
              </div>
              <h2 id="sheet-title">
                {sheet.kind === "reading"
                  ? "What does it read?"
                  : sheet.kind === "note"
                    ? "What did you notice?"
                    : sheet.kind === "override"
                      ? "Explain the override."
                      : sheet.kind === "auth"
                        ? "Enter your access token."
                        : "Say what you’ll do next."}
              </h2>
              <p>
                {sheet.kind === "note"
                  ? "Your observation stays pinned to the equipment for the next shift."
                  : sheet.kind === "override"
                    ? "A HOLD requires an explicit reason. This decision is recorded in the audit trail."
                    : sheet.kind === "auth"
                      ? "This server is protected by DIRECTOR_TOKEN."
                      : "A specific next action closes the loop."}
              </p>
              {sheet.kind === "reading" ? (
                <>
                  <div className="reading-input">
                    <input
                      autoFocus
                      aria-label="Reading value"
                      inputMode="decimal"
                      value={text}
                      onChange={(e) => setText(e.target.value)}
                    />
                    <span>{s.assets.find((a) => a.id === sheet.id)?.unit}</span>
                  </div>
                  {Number.isFinite(Number(text)) && (
                    <p className="baseline-feedback">
                      {(
                        Number(text) -
                        (s.assets.find((a) => a.id === sheet.id)?.baseline ?? 0)
                      ).toFixed(1)}{" "}
                      vs your baseline
                    </p>
                  )}
                  <div className="keypad">
                    {[
                      "1",
                      "2",
                      "3",
                      "4",
                      "5",
                      "6",
                      "7",
                      "8",
                      "9",
                      ".",
                      "0",
                      "⌫",
                    ].map((key) => (
                      <button
                        key={key}
                        onClick={() =>
                          setText(key === "⌫" ? text.slice(0, -1) : text + key)
                        }
                      >
                        {key}
                      </button>
                    ))}
                  </div>
                </>
              ) : sheet.kind === "auth" ? (
                <input
                  type="password"
                  autoFocus
                  aria-label="Access token"
                  value={text}
                  onChange={(e) => setText(e.target.value)}
                />
              ) : (
                <>
                  <textarea
                    autoFocus
                    aria-label={
                      sheet.kind === "note"
                        ? "Field note"
                        : "Read-back or override reason"
                    }
                    placeholder={
                      sheet.kind === "note"
                        ? "Pump B is rattling, louder than yesterday…"
                        : "I’ll check pump B bearing by 02:30…"
                    }
                    value={text}
                    onChange={(e) => setText(e.target.value)}
                    rows={4}
                  />
                  <button className="voice-button" onClick={voice}>
                    <Mic size={18} />
                    {listening ? "Listening…" : "Use your voice"}
                  </button>
                </>
              )}
              {error && (
                <p role="alert" className="amber-text">
                  {error}
                </p>
              )}
              <button
                disabled={
                  busy ||
                  !text.trim() ||
                  (sheet.kind === "reading" && !Number.isFinite(Number(text)))
                }
                className="button primary full"
                onClick={() => {
                  if (sheet.kind === "auth") {
                    void login();
                    return;
                  }
                  if (sheet.kind === "reading")
                    void send(
                      {
                        type: "reading",
                        assetId: sheet.id,
                        value: Number(text),
                      },
                      "Reading logged and checked against baseline",
                    );
                  if (sheet.kind === "note")
                    void send(
                      { type: "note", assetId: sheet.id, text },
                      "Field note pinned to the asset",
                    );
                  if (sheet.kind === "ack")
                    void send(
                      { type: "ack", warningId: sheet.id, readback: text },
                      "Ownership confirmed with your read-back",
                    );
                  if (sheet.kind === "confirm")
                    void send(
                      { type: "confirm", itemId: sheet.id, readback: text },
                      "Handover item confirmed",
                    );
                  if (sheet.kind === "override")
                    void send(
                      {
                        type: "advance",
                        runId: sheet.id,
                        overrideReason: text,
                      },
                      "Override recorded",
                    );
                }}
              >
                {busy
                  ? "Saving…"
                  : sheet.kind === "note"
                    ? "Pin note"
                    : sheet.kind === "reading"
                      ? "Save reading"
                      : sheet.kind === "override"
                        ? "Record override and continue"
                        : sheet.kind === "auth"
                          ? "Use access token"
                          : "Confirm read-back"}
                <Check size={18} />
              </button>
            </motion.section>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function ProcedureView({
  state: s,
  busy,
  send,
  open,
}: {
  state: PlantState;
  busy: boolean;
  send: (c: Command, message?: string) => Promise<unknown>;
  open: (kind: Sheet["kind"], id: string, value?: string) => void;
}) {
  const [selected, setSelected] = useState("");
  const [assetId, setAssetId] = useState("");
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    setSelected(params.get("procedure") ?? "");
    setAssetId(params.get("asset") ?? "");
  }, []);
  const p = s.procedures.find((p) => p.id === selected);
  const run = p
    ? s.runs
        .filter((r) => r.procedureId === p.id && r.assetId === assetId)
        .at(-1)
    : undefined;
  const step = p?.steps.find((st) => st.number === (run?.step ?? 1));
  return (
    <div className="procedure-layout">
      <ProcedureCompiler />
      <section className="card procedure-library">
        <h3>Procedure library</h3>
        {s.procedures.map((p) => (
          <button
            className={`procedure-link ${selected === p.id ? "selected" : ""}`}
            onClick={() => setSelected(p.id)}
            key={p.id}
          >
            <BookOpen size={19} />
            <div>
              <strong>{p.title}</strong>
              <p>
                Rev {p.version} · {p.steps.length} steps ·{" "}
                {p.approved ? "Approved" : "Unapproved"}
              </p>
            </div>
            <ChevronRight size={16} />
          </button>
        ))}
      </section>
      <div>
        {p ? (
          <>
            <section className="card procedure-run">
              <div className="row-between">
                <Badge tone="mint">
                  <ShieldCheck size={14} /> PROCEDURE GUARDIAN
                </Badge>
                <span className="micro">REV {p.version}</span>
              </div>
              <h2>{p.title}</h2>
              <label className="form-label">
                Equipment
                <select
                  aria-label="Procedure equipment"
                  value={assetId}
                  onChange={(e) => setAssetId(e.target.value)}
                >
                  <option value="">Choose asset</option>
                  {s.assets.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name} · {a.id}
                    </option>
                  ))}
                </select>
              </label>
              <div className="step-progress">
                {p.steps.map((st) => (
                  <span
                    key={st.number}
                    className={st.number <= (run?.step ?? 0) ? "done" : ""}
                  />
                ))}
              </div>
              <div className="step-label">
                STEP {step?.number ?? 1} OF {p.steps.length}
              </div>
              <h2>{run?.completed ? "Procedure completed" : step?.text}</h2>
              {step && <p>Verify: {step.verification}</p>}
              {run && (
                <div
                  className={`verdict ${run.verdict === "HOLD" ? "hold" : "go"}`}
                >
                  <div>
                    {run.verdict === "HOLD" ? (
                      <ShieldAlert size={26} />
                    ) : (
                      <ShieldCheck size={26} />
                    )}
                    <strong>{run.verdict}</strong>
                  </div>
                  <p>{run.reasoning}</p>
                  <details>
                    <summary>Why this decision?</summary>
                    <p>
                      Checked against live plant state, active maintenance, and
                      the action’s topology impact.
                    </p>
                    {step?.preconditions.map((c) => (
                      <p key={c}>{c}</p>
                    ))}
                  </details>
                </div>
              )}
              {!run ? (
                <button
                  className="button primary full"
                  disabled={!assetId || busy || !p.approved}
                  onClick={() =>
                    void send(
                      { type: "check", procedureId: p.id, assetId, step: 1 },
                      "Live preconditions checked",
                    )
                  }
                >
                  <ShieldCheck size={18} />
                  Check this step
                </button>
              ) : !run.completed ? (
                <div className="button-row">
                  <button
                    className="button primary"
                    disabled={busy || run.verdict === "HOLD"}
                    onClick={() =>
                      void send(
                        { type: "advance", runId: run.id },
                        "Step advanced and next preconditions checked",
                      )
                    }
                  >
                    Confirm step complete <ArrowRight size={18} />
                  </button>
                  {run.verdict === "HOLD" && (
                    <button
                      className="button danger"
                      onClick={() => open("override", run.id)}
                    >
                      Override with reason
                    </button>
                  )}
                </div>
              ) : (
                <Badge tone="mint">
                  <CheckCheck size={16} />
                  All steps recorded
                </Badge>
              )}
            </section>
            <div className="caption">
              <ShieldCheck size={16} />
              Steps record human work. The app never operates the plant.
            </div>
          </>
        ) : (
          <Empty
            title="Choose the procedure for this job"
            detail="Each step is checked against the plant before you proceed."
          />
        )}
      </div>
    </div>
  );
}
function TagCard({ asset }: { asset: Asset }) {
  const [qr, setQr] = useState("");
  const [url, setUrl] = useState("");
  useEffect(() => {
    const href = `${window.location.origin}/a/${asset.id}`;
    setUrl(href);
    void QRCode.toDataURL(href, {
      width: 300,
      margin: 2,
      color: { dark: "#080809", light: "#f8f8ff" },
    }).then(setQr);
  }, [asset.id]);
  return (
    <Link className="card tag-card" href={`/a/${asset.id}`}>
      {qr ? (
        <img
          src={qr}
          alt={`QR code for ${asset.name}`}
          width={180}
          height={180}
        />
      ) : (
        <QrCode size={160} />
      )}
      <h3>{asset.name}</h3>
      <Badge>{asset.id}</Badge>
      <small>{url}</small>
    </Link>
  );
}
