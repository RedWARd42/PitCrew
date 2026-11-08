import type {
  Asset,
  PlantState,
  Procedure,
  TelemetrySource,
} from "../../packages/contracts";
import seed from "../../data/seed-site.json";

export function random(seedValue: number) {
  let x = seedValue >>> 0;
  return () => {
    x = (1664525 * x + 1013904223) >>> 0;
    return x / 4294967296;
  };
}
function asset(
  id: string,
  name: string,
  type: string,
  baseline: number,
  unit: string,
  metric: string,
  routeOrder: number,
  feeds: string[] = [],
): Asset {
  const rng = random(id.split("").reduce((s, c) => s + c.charCodeAt(0), 42));
  return {
    id,
    name,
    type,
    zone: "Hall 2",
    criticality: type === "row" ? 5 : 3,
    status: "online",
    routeOrder,
    metric,
    unit,
    baseline,
    value: baseline,
    history: Array.from(
      { length: 30 },
      () => baseline + (rng() - 0.5) * baseline * 0.01,
    ),
    feeds,
  };
}
const makeStep = (
  number: number,
  text: string,
  target: string,
  type: "inspect" | "open_breaker" | "stop" = "inspect",
) => ({
  number,
  text,
  action: { type, target },
  preconditions: type === "inspect" ? [] : ["retain_last_source"],
  hazards: type === "inspect" ? [] : ["Loss of source"],
  verification: "Verify local indication and record read-back.",
});
export const procedures: Procedure[] = [
  {
    id: "MOP-UPS",
    title: "UPS-2 maintenance bypass & PDU-4 isolation",
    assetTypes: ["ups", "pdu"],
    version: 2,
    approved: true,
    steps: [
      makeStep(
        1,
        "Confirm approved maintenance window and work permit",
        "UPS-2",
      ),
      makeStep(2, "Read local UPS status and record all active work", "UPS-2"),
      makeStep(3, "Verify alternate source is online", "UPS-1"),
      makeStep(4, "Check Row D load and redundant feed indications", "Row-D"),
      makeStep(5, "Notify chief engineer before isolation", "PDU-4"),
      makeStep(6, "Open breaker B at PDU-4", "PDU-4", "open_breaker"),
      makeStep(7, "Verify isolation and complete the work record", "PDU-4"),
    ],
  },
  {
    id: "MOP-PUMP",
    title: "CHW pump swap",
    assetTypes: ["chiller", "pump"],
    version: 3,
    approved: true,
    steps: [
      makeStep(1, "Verify standby pump pressure and flow", "P-3"),
      makeStep(
        2,
        "Confirm pump B bearing inspection with mechanical lead",
        "CH-3",
      ),
      makeStep(
        3,
        "Stop pump only after independent cooling path is verified",
        "P-2",
        "stop",
      ),
    ],
  },
  {
    id: "EOP-CHILLER",
    title: "Chiller restart after trip",
    assetTypes: ["chiller"],
    version: 4,
    approved: true,
    steps: [
      makeStep(
        1,
        "Confirm voltage stabilized and notify chief engineer",
        "CH-1",
      ),
      {
        ...makeStep(
          2,
          "Verify chilled water supply remains below restart limit of 62°F",
          "CDU-1",
        ),
        preconditions: ["temperature_below_62"],
      },
      makeStep(
        3,
        "Request authorized operator restart; verify plant locally",
        "CH-3",
      ),
    ],
  },
  {
    id: "MOP-BAT",
    title: "Battery string impedance test",
    assetTypes: ["battery"],
    version: 2,
    approved: true,
    steps: [
      makeStep(1, "Verify PPE and approved battery test permit", "BAT-3"),
      makeStep(
        2,
        "Measure each cell; compare against its own baseline",
        "BAT-3",
      ),
      makeStep(
        3,
        "Escalate impedance drift even if voltage is normal",
        "BAT-3",
      ),
    ],
  },
  {
    id: "MOP-CDU",
    title: "CDU filter change",
    assetTypes: ["cdu"],
    version: 1,
    approved: true,
    steps: [
      makeStep(1, "Verify standby coolant path and leak detection", "CDU-1"),
      makeStep(
        2,
        "Inspect filter differential pressure without isolating flow",
        "CDU-1",
      ),
    ],
  },
  {
    id: "MOP-UPS-OLD",
    title: "UPS-2 maintenance bypass (superseded)",
    assetTypes: ["ups"],
    version: 1,
    approved: false,
    steps: [makeStep(1, "Verify old work instructions", "UPS-2")],
  },
];
export function createInitialState(): PlantState {
  const assets = [
    asset("CH-1", "Chiller 1", "chiller", 4, "°F", "Approach temperature", 2),
    asset("CH-2", "Chiller 2", "chiller", 4.1, "°F", "Approach temperature", 3),
    asset("CH-3", "Chiller 3", "chiller", 4, "°F", "Approach temperature", 1),
    asset("UPS-1", "UPS 1", "ups", 42, "%", "Load", 4),
    asset("UPS-2", "UPS 2", "ups", 41, "%", "Load", 5),
    asset("PDU-4", "PDU 4 · Breaker B", "pdu", 180, "kW", "Power", 6, [
      "UPS-1",
    ]),
    asset("Row-D", "AI Row D", "row", 180, "kW", "IT load", 7, [
      "PDU-4",
      "UPS-2",
    ]),
    asset("BAT-3", "VRLA string 3", "battery", 3.2, "mΩ", "Cell impedance", 8),
    asset("CRAH-1", "CRAH 1", "crah", 74, "°F", "Return air", 9),
    asset("CRAH-2", "CRAH 2", "crah", 74.1, "°F", "Return air", 10),
    asset("CRAH-3", "CRAH 3", "crah", 73.9, "°F", "Return air", 11),
    asset(
      "CDU-1",
      "Row D coolant distribution",
      "cdu",
      48,
      "°F",
      "CHW supply",
      12,
    ),
    ...["P-1", "P-2", "P-3"].map((id, index) =>
      asset(
        id,
        `CHW pump ${index + 1}`,
        "pump",
        45,
        "psi",
        "Discharge pressure",
        13 + index,
      ),
    ),
  ];
  const state: PlantState = {
    investigations: [],
    clock: seed.clock,
    scenario: null,
    paused: true,
    cacheMode:
      process.env.DEMO_CACHE === "prefer"
        ? "prefer"
        : process.env.DEMO_CACHE === "live"
          ? "live"
          : "only",
    assets,
    people: seed.people,
    notes: [
      {
        id: "note-seed",
        assetId: "CH-3",
        author: "Day shift · Jordan",
        text: "Rattle near pump B. Louder under load. Please check bearing on night rounds.",
        ts: "2026-11-08T04:30:00.000Z",
        structured: {
          component: "pump B bearing",
          symptom: "rattle under load",
          severity: "watch",
          followUp: true,
        },
      },
      {
        id: "note-ups-maintenance",
        assetId: "UPS-2",
        author: "Day shift · Jordan",
        text: "UPS-2 bypass maintenance is scheduled for 02:00. Verify the permit and alternate feed before starting; UPS remains online.",
        ts: "2026-11-08T05:15:00.000Z",
        structured: {
          component: "maintenance permit and alternate feed",
          symptom: "planned bypass maintenance at 02:00",
          severity: "watch",
          followUp: true,
        },
      },
      {
        id: "note-cdu-filter",
        assetId: "CDU-1",
        author: "Day shift · Casey",
        text: "CDU filter differential pressure needs a repeat reading on the incoming round. No leak or flow alarm; leave both coolant paths available.",
        ts: "2026-11-08T05:30:00.000Z",
        structured: {
          component: "filter differential pressure",
          symptom: "repeat reading due on incoming round",
          severity: "watch",
          followUp: true,
        },
      },
    ],
    warnings: [],
    incidents: [],
    procedures: structuredClone(procedures),
    messages: [],
    traces: [],
    handover: [],
    workOrders: [],
    runs: [],
    audit: [],
  };
  state.handover = state.notes.map((note) => ({
    id: `handover-${note.id}`,
    assetId: note.assetId,
    severity: note.structured.severity,
    summary: note.text,
    action: `Inspect ${note.structured.component} and record findings.`,
    contingency: "Contact the on-call chief if the condition deteriorates.",
    confirmed: false,
    readback: "",
  }));
  return state;
}
export function applyScenario(state: PlantState, id: string) {
  state.scenario = id;
  const get = (assetId: string) => state.assets.find((a) => a.id === assetId)!;
  if (id === "S1") {
    const a = get("CH-3");
    a.value = a.baseline + 1.5;
    a.history = Array.from(
      { length: 121 },
      (_, i) => a.baseline + (i * 1.5) / 120,
    );
    a.status = "watch";
  } else if (id === "S2") {
    get("UPS-2").status = "bypass";
  } else if (id === "S3") {
    get("CH-1").status = "tripped";
    get("CH-2").status = "tripped";
    get("CH-3").status = "failed";
    const a = get("CDU-1");
    a.value = 55;
    a.history = Array.from({ length: 15 }, (_, i) => 48 + i * 0.5);
    a.status = "critical";
  } else if (id === "S4") {
    const a = get("BAT-3");
    a.value = a.baseline * 1.15;
    a.history = Array.from(
      { length: 22 },
      (_, i) => a.baseline * (1 + (i * 0.15) / 21),
    );
    a.status = "watch";
  } else if (id === "S5") {
    get("CRAH-1").value = 82;
    get("CRAH-1").history.push(82);
    get("CRAH-1").status = "sensor suspect";
  }
}
export function scenarioAlarms(state: PlantState) {
  return state.scenario === "S3"
    ? Array.from({ length: 47 }, (_, i) => ({
        assetId:
          i === 0
            ? "UPS-1"
            : ["CH-1", "CH-2", "CH-3", "CDU-1", "CRAH-1"][i % 5]!,
        code:
          i === 0
            ? "voltage_dip"
            : i % 3 === 0
              ? "failed_start"
              : "downstream_high_temp",
        ts: new Date(Date.parse(state.clock) + i * 1800).toISOString(),
      }))
    : [];
}
export function advanceSimulation(state: PlantState, seconds: number) {
  state.clock = new Date(
    Date.parse(state.clock) + seconds * 1000,
  ).toISOString();
  if (state.scenario === "S3") {
    const a = state.assets.find((x) => x.id === "CDU-1")!;
    a.value += seconds / 120;
    a.history.push(a.value);
    for (const incident of state.incidents) {
      incident.etaMinutes = Math.max(0, (62 - a.value) / 0.5);
      incident.confidence = [
        incident.etaMinutes * 0.9,
        incident.etaMinutes * 1.1,
      ];
    }
  }
}
export class PlantSimulator implements TelemetrySource {
  private listeners = new Set<(asset: Asset) => void>();
  constructor(public state = createInitialState()) {}
  snapshot(ids?: string[]) {
    return structuredClone(
      this.state.assets.filter((a) => !ids || ids.includes(a.id)),
    );
  }
  subscribe(listener: (asset: Asset) => void) {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }
  step(seconds = 1) {
    advanceSimulation(this.state, seconds);
    this.snapshot().forEach((a) =>
      this.listeners.forEach((listener) => listener(a)),
    );
  }
}
