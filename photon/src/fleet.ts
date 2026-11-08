/**
 * The Swat fleet brain, ported 1:1 from the Flutter app's Dart engine
 * (lib/services/scam_analyzer.dart) so the drones give the same verdicts
 * on Photon channels as they do in the app. Pure logic, no I/O.
 *
 * Calibration (identical to the app): T-Mobile smish 100, genuine 456
 * bill 0, Chase smish 68, USPS smish 64.
 */

export type DroneId =
  | "angler"
  | "link"
  | "scanner"
  | "pressure"
  | "impersonator"
  | "swap";

export interface DroneInfo {
  id: DroneId;
  label: string;
  specialty: string;
  lesson: string;
}

export const DRONES: DroneInfo[] = [
  {
    id: "angler",
    label: "Angler",
    specialty: "Spoofed senders",
    lesson:
      "Real companies text alerts from registered short codes, not random " +
      "phone numbers. If a 'bank' texts you from an ordinary number, treat " +
      "the message as guilty until proven innocent.",
  },
  {
    id: "link",
    label: "Link",
    specialty: "Fake links & domains",
    lesson:
      "Read a domain right-to-left: the real owner is the word right " +
      "before .com. 't-mobile-verify-secure.com' is not T-Mobile — " +
      "'t-mobile.com' is. One extra word makes it a different site.",
  },
  {
    id: "scanner",
    label: "Scanner",
    specialty: "QR codes & attachments",
    lesson:
      "A QR code hides its destination until it opens — never scan one " +
      "from an unexpected text to 'verify' anything. Open the official " +
      "app yourself instead.",
  },
  {
    id: "pressure",
    label: "Pressure",
    specialty: "Urgency & threats",
    lesson:
      "Scams always rush you. A real company gives you time, a statement, " +
      "and other ways to reach them. Urgency is the tell, not the reason.",
  },
  {
    id: "impersonator",
    label: "Impersonator",
    specialty: "Brand impersonation",
    lesson:
      "No carrier or bank will ever ask for your PIN, password, or card " +
      "number by text. The request itself is the scam, whoever it claims " +
      "to be from.",
  },
  {
    id: "swap",
    label: "Swap",
    specialty: "SIM-swap & code fishing",
    lesson:
      "Never share a verification code that arrived by text with anyone " +
      "who asks for it — that is exactly how a number gets taken over. " +
      "Set a SIM lock and account PIN inside the official app.",
  },
];

export const droneById = (id: DroneId): DroneInfo =>
  DRONES.find((d) => d.id === id)!;

export const droneByName = (name: string): DroneInfo | undefined =>
  DRONES.find((d) => d.label.toLowerCase() === name.toLowerCase());

export interface Finding {
  drone: DroneId;
  title: string;
  detail: string;
  points: number;
}

export interface Analysis {
  riskScore: number;
  confidence: number;
  findings: Finding[];
  verdict: "dangerous" | "caution" | "safe";
}

interface Brand {
  name: string;
  officialDomains: string[];
  officialShortCodes: string[];
  aliases: string[];
}

const knownBrands: Brand[] = [
  {
    name: "T-Mobile",
    officialDomains: ["t-mobile.com", "tmobile.com", "t-mobile.mymobileapp.com"],
    officialShortCodes: ["456", "2294", "4629"],
    aliases: ["t-mobile", "tmobile", "t mobile"],
  },
  {
    name: "Chase",
    officialDomains: ["chase.com", "jpmorganchase.com"],
    officialShortCodes: ["24273", "33748"],
    aliases: ["chase", "jpmorgan"],
  },
  {
    name: "Bank of America",
    officialDomains: ["bankofamerica.com", "bofa.com"],
    officialShortCodes: ["692632"],
    aliases: ["bank of america", "bofa"],
  },
  {
    name: "USPS",
    officialDomains: ["usps.com"],
    officialShortCodes: ["28777"],
    aliases: ["usps", "u.s. postal", "postal service"],
  },
  {
    name: "UPS",
    officialDomains: ["ups.com"],
    officialShortCodes: ["69877"],
    aliases: ["ups"],
  },
  {
    name: "FedEx",
    officialDomains: ["fedex.com"],
    officialShortCodes: ["29372"],
    aliases: ["fedex"],
  },
  {
    name: "Amazon",
    officialDomains: ["amazon.com", "amazon.co.uk"],
    officialShortCodes: ["262966"],
    aliases: ["amazon"],
  },
  {
    name: "Apple",
    officialDomains: ["apple.com", "icloud.com"],
    officialShortCodes: [],
    aliases: ["apple", "icloud"],
  },
  {
    name: "IRS",
    officialDomains: ["irs.gov"],
    officialShortCodes: [],
    aliases: ["irs", "internal revenue"],
  },
];

const urlShorteners = new Set([
  "bit.ly",
  "tinyurl.com",
  "t.co",
  "goo.gl",
  "rb.gy",
  "is.gd",
  "cutt.ly",
  "shorturl.at",
]);

function claimedBrand(sender: string, body: string): Brand | null {
  const text = `${sender} ${body}`.toLowerCase();
  for (const brand of knownBrands) {
    if (brand.aliases.some((a) => text.includes(a))) return brand;
  }
  return null;
}

// ------------------------------------------------------------------ Angler
function angler(sender: string, body: string): Finding[] {
  const brand = claimedBrand(sender, body);
  const s = sender.trim();
  const isShortCode = /^\d{3,6}$/.test(s);
  const isLongNumber = /^\+?\d[\d\s\-()]{6,}$/.test(s);

  if (brand && brand.officialShortCodes.includes(s)) {
    return [
      {
        drone: "angler",
        title: "Verified sender",
        detail:
          `This came from ${s}, a registered ${brand.name} short code. ` +
          "Carriers verify who can send from a short code, so this is a " +
          `strong sign the message is really from ${brand.name}.`,
        points: 0,
      },
    ];
  }
  if (brand && isLongNumber) {
    return [
      {
        drone: "angler",
        title: "Spoofed sender",
        detail:
          `The message claims to be ${brand.name}, but it came from an ` +
          `ordinary phone number (${s}). ${brand.name} sends account ` +
          "alerts from a registered short code" +
          (brand.officialShortCodes.length
            ? ` (e.g. ${brand.officialShortCodes[0]})`
            : "") +
          ", not from a random number. Scammers rent numbers like this " +
          "by the thousand.",
        points: 34,
      },
    ];
  }
  if (brand && !isShortCode) {
    return [
      {
        drone: "angler",
        title: "Unverified sender name",
        detail:
          `The sender shows as "${s}", but display names can be set to ` +
          "anything — they are not verified by the carrier.",
        points: 18,
      },
    ];
  }
  if (!sender) {
    return [
      {
        drone: "angler",
        title: "Sender not shared",
        detail:
          "You pasted the message without its sender. Tell me the number " +
          "or name it came from (reply 'from +1 …') and I will run the " +
          "sender check too.",
        points: 0,
      },
    ];
  }
  return [
    {
      drone: "angler",
      title: "Sender check passed",
      detail:
        "Nothing about the sender contradicts who the message claims " +
        "to be.",
      points: 0,
    },
  ];
}

// -------------------------------------------------------------------- Link
const urlPattern = /((?:https?:\/\/)?(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:\/[^\s]*)?)/g;

function extractUrls(text: string): string[] {
  const urls: string[] = [];
  for (const match of text.matchAll(urlPattern)) {
    const url = match[0].replace(/[.,;:!?\)\]]+$/, "");
    if (url.includes(".") && !url.startsWith(" ")) urls.push(url);
  }
  return urls;
}

function hostOf(url: string): string {
  const u = url.toLowerCase().replace(/^https?:\/\//, "");
  return u.split("/")[0].split("?")[0];
}

function isOfficial(host: string, brand: Brand): boolean {
  return brand.officialDomains.some((d) => host === d || host.endsWith(`.${d}`));
}

function judgeUrl(
  sender: string,
  body: string,
  url: string,
  drone: DroneId,
): Finding {
  const host = hostOf(url);
  const brand = claimedBrand(sender, body);

  if (urlShorteners.has(host)) {
    return {
      drone,
      title: "Shortened link hides its destination",
      detail:
        `"${host}" is a link shortener — the real destination is hidden ` +
        "until you tap. Legit account alerts almost never hide where a " +
        "link goes.",
      points: 22,
    };
  }
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) {
    return {
      drone,
      title: "Link goes to a raw IP address",
      detail:
        "The link points at a bare IP address instead of a company " +
        "domain. Real companies do not run login pages on raw IPs.",
      points: 30,
    };
  }
  if (host.includes("xn--")) {
    return {
      drone,
      title: "Lookalike characters in domain",
      detail:
        "This domain uses encoded characters (punycode) that can render " +
        "as letters that look like a real brand but are not.",
      points: 28,
    };
  }
  if (brand) {
    if (isOfficial(host, brand)) {
      return {
        drone,
        title: "Official domain",
        detail:
          `${host} is a real ${brand.name} domain. Links in genuine ` +
          "alerts stay on the company's own domain.",
        points: 0,
      };
    }
    const squashed = host.replaceAll("-", "").replaceAll(".", "");
    const brandSquashed = brand.name.toLowerCase().replace(/[^a-z]/g, "");
    if (
      squashed.includes(brandSquashed) ||
      brand.aliases.some(
        (a) => host.includes(a.replaceAll(" ", "-")) || host.includes(a.replaceAll(" ", "")),
      )
    ) {
      return {
        drone,
        title: "Lookalike domain",
        detail:
          `"${host}" is built to look like ${brand.name}, but it is NOT ` +
          `a ${brand.name} domain. The real one is ` +
          `${brand.officialDomains[0]}. One extra word or hyphen in the ` +
          "domain means a completely different — and fake — site.",
        points: 36,
      };
    }
    return {
      drone,
      title: "Off-brand domain",
      detail:
        `The message claims to be ${brand.name} but links to "${host}", ` +
        `which is not a ${brand.name} domain.`,
      points: 30,
    };
  }
  return {
    drone,
    title: "Link present",
    detail:
      `This message contains a link to ${host}. No brand is claimed, ` +
      "so judge it by whether you were expecting it.",
    points: 6,
  };
}

function link(sender: string, body: string): Finding[] {
  const urls = extractUrls(body);
  if (urls.length === 0) {
    return [
      {
        drone: "link",
        title: "No links",
        detail:
          "There is no link in this message to tap — a scam's favorite " +
          "trap is missing.",
        points: 0,
      },
    ];
  }
  return urls.map((url) => judgeUrl(sender, body, url, "link"));
}

// ----------------------------------------------------------------- Scanner
function scanner(body: string): Finding[] {
  const findings: Finding[] = [];
  const qrMention = /scan (the )?(qr|code)/i.exec(body);
  if (qrMention) {
    findings.push({
      drone: "scanner",
      title: "Pushes you to scan a QR code",
      detail:
        "The message tells you to scan a QR code. A QR code hides its " +
        "destination even better than a link — you cannot read where it " +
        "goes before it opens. Carriers and banks do not ask you to " +
        'scan QR codes from a text to "verify" an account.',
      points: 12,
    });
  }
  if (findings.length === 0) {
    findings.push({
      drone: "scanner",
      title: "No QR code",
      detail: "No QR code attached to or mentioned in this message.",
      points: 0,
    });
  }
  return findings;
}

// ---------------------------------------------------------------- Pressure
const pressurePhrases: Array<[string, string]> = [
  ["within 24 hours", "a hard 24-hour deadline"],
  ["within 12 hours", "a hard 12-hour deadline"],
  ["suspended", "a threat to suspend the account/line"],
  ["will be closed", "a threat to close the account"],
  ["will be locked", "a threat to lock the account/card"],
  ["immediately", '"immediately"'],
  ["act now", '"act now"'],
  ["urgent", '"urgent"'],
  ["final notice", '"final notice"'],
  ["verify now", '"verify now"'],
  ["expires today", "a same-day expiry"],
  ["last chance", '"last chance"'],
];

function capsRatio(text: string): number {
  const letters = text.replace(/[^a-zA-Z]/g, "");
  if (!letters.length) return 0;
  return letters.replace(/[^A-Z]/g, "").length / letters.length;
}

function pressure(body: string): Finding[] {
  const lower = body.toLowerCase();
  const labels: string[] = [];
  for (const [phrase, label] of pressurePhrases) {
    if (lower.includes(phrase)) labels.push(label);
  }
  if (labels.length === 0) {
    return [
      {
        drone: "pressure",
        title: "Calm tone",
        detail:
          "No deadlines, threats, or rush language. Real notices tell " +
          "you what happened; scams tell you to hurry.",
        points: 0,
      },
    ];
  }
  const points = Math.min(
    30,
    Math.max(0, labels.length * 9 + (capsRatio(body) > 0.25 ? 6 : 0)),
  );
  return [
    {
      drone: "pressure",
      title: `Pressure tactics (${labels.length})`,
      detail:
        `This message rushes you with ${labels.join(", ")}. That is ` +
        "deliberate: the FTC's scam script always adds pressure so you " +
        "act before you think. A real company gives you time and other " +
        "ways to reach them.",
      points,
    },
  ];
}

// ------------------------------------------------------------ Impersonator
function impersonator(body: string): Finding[] {
  const findings: Finding[] = [];
  const lower = body.toLowerCase();

  const credentialAsk =
    /(account pin|your pin|password|social security|ssn|card number|cvv)/i.exec(body);
  if (credentialAsk && /(enter|confirm|verify|share|send|provide|reply)/i.test(lower)) {
    findings.push({
      drone: "impersonator",
      title: "Asks for a secret only you should know",
      detail:
        `The message asks you to hand over a "${credentialAsk[0]}". No ` +
        "carrier or bank will ever ask for that by text — the request " +
        "itself is the scam, whoever it claims to be from.",
      points: 32,
    });
  }

  const paymentAsk =
    /(gift card|wire transfer|western union|bitcoin|crypto|zelle.*stranger)/i.exec(body);
  if (paymentAsk) {
    findings.push({
      drone: "impersonator",
      title: "Unusual payment method demanded",
      detail:
        `It steers you toward paying by ${paymentAsk[0]} — the payment ` +
        "rail scammers use because it cannot be reversed.",
      points: 30,
    });
  }

  if (findings.length === 0) {
    const brand = claimedBrand("", body);
    findings.push({
      drone: "impersonator",
      title: brand ? "Identity claim checked" : "No impersonation tells",
      detail: brand
        ? `The message claims to be ${brand.name}. Read with Angler's ` +
          "sender check and Link's domain check — an impersonator " +
          "usually fails at least one of them."
        : "The message does not pretend to be a company or official.",
      points: 0,
    });
  }
  return findings;
}

// -------------------------------------------------------------------- Swap
function swap(body: string): Finding[] {
  const findings: Finding[] = [];
  const codeAsk =
    /(6-digit code|verification code|one-time code|the code we (sent|texted))/i.exec(body);
  if (codeAsk && /(send|share|enter|confirm|reply|give)/i.test(body)) {
    findings.push({
      drone: "swap",
      title: "Verification-code fishing",
      detail:
        "It fishes for a verification code. Those codes are how a " +
        "scammer takes over your number (a SIM-swap / port-out): they " +
        "trigger a code to your phone, then talk you into handing it " +
        "over. Never share a code that a text message itself sent you " +
        "with anyone who asks for it.",
      points: 34,
    });
  }
  const simTalk =
    /(sim (card )?(will|swap|replace)|port (out|your number)|keep your number active|line will be)/i.exec(body);
  if (simTalk) {
    findings.push({
      drone: "swap",
      title: "Number-takeover framing",
      detail:
        "The message talks about your line/number being changed or " +
        "deactivated. That framing primes you for a SIM-swap pitch. " +
        "Your real protection: a SIM-swap lock and account PIN set " +
        "inside the official app — never through a texted link.",
      points: 18,
    });
  }
  if (findings.length === 0) {
    findings.push({
      drone: "swap",
      title: "No SIM-swap tells",
      detail:
        "Nothing here fishes for a verification code or primes a " +
        "number takeover.",
      points: 0,
    });
  }
  return findings;
}

// ------------------------------------------------------------------ scoring
export function scoreFindings(findings: Finding[]): [number, number] {
  const flagPoints = findings
    .filter((f) => f.points > 0)
    .map((f) => f.points)
    .sort((a, b) => b - a);
  let risk = 0;
  flagPoints.forEach((p, i) => {
    risk += p * (i === 0 ? 1.0 : i === 1 ? 0.7 : 0.45);
  });
  const riskScore = Math.min(100, Math.max(0, Math.round(risk)));
  const flagging = new Set(findings.filter((f) => f.points > 0).map((f) => f.drone)).size;
  const confidence =
    flagging === 0 ? 92 : Math.min(97, Math.max(55, 55 + flagging * 12));
  return [riskScore, confidence];
}

/** Run the whole fleet over one message. Sender may be "" if unknown. */
export function analyzeMessage(sender: string, body: string): Analysis {
  const findings: Finding[] = [
    ...angler(sender, body),
    ...link(sender, body),
    ...scanner(body),
    ...pressure(body),
    ...impersonator(body),
    ...swap(body),
  ];
  const [riskScore, confidence] = scoreFindings(findings);
  return {
    riskScore,
    confidence,
    findings,
    verdict: riskScore >= 60 ? "dangerous" : riskScore >= 30 ? "caution" : "safe",
  };
}

export function pointsFor(analysis: Analysis, drone: DroneId): number {
  return analysis.findings
    .filter((f) => f.drone === drone)
    .reduce((sum, f) => sum + f.points, 0);
}

// ------------------------------------------------------- chat formatting
/** One-paragraph fleet verdict for a chat channel (iMessage/SMS/etc). */
export function formatAnalysis(analysis: Analysis): string {
  const flagging = DRONES.filter((d) => pointsFor(analysis, d.id) > 0);
  const headline =
    analysis.verdict === "dangerous"
      ? `🚨 SCAM — ${analysis.riskScore}/100 risk. Do not tap anything in it.`
      : analysis.verdict === "caution"
        ? `⚠️ Suspicious — ${analysis.riskScore}/100 risk. Slow down and verify first.`
        : `✅ Looks legit — ${analysis.riskScore}/100 risk.`;
  const lines: string[] = [
    `🛡️ Swat fleet report — confidence ${analysis.confidence}%`,
    headline,
    "",
  ];
  if (flagging.length === 0) {
    lines.push("All six drones checked it and found nothing:");
    for (const d of DRONES) {
      const f = analysis.findings.find((x) => x.drone === d.id);
      lines.push(`• ${d.label}: ${f?.title ?? "clear"}`);
    }
  } else {
    lines.push(
      `${flagging.length} of 6 drones flagged something:`,
    );
    for (const d of flagging) {
      const pts = pointsFor(analysis, d.id);
      const top = analysis.findings
        .filter((f) => f.drone === d.id && f.points > 0)
        .sort((a, b) => b.points - a.points)[0];
      lines.push(`• ${d.label} +${pts} — ${top.title}. ${top.detail}`);
    }
    const clear = DRONES.filter((d) => pointsFor(analysis, d.id) === 0);
    if (clear.length) {
      lines.push(`Clear: ${clear.map((d) => d.label).join(", ")}.`);
    }
  }
  lines.push("");
  lines.push(
    analysis.verdict === "safe"
      ? "No action needed. If you're ever unsure, open the company's official app yourself — never through a link in the message."
      : "What to do: don't open links or scan codes from it, don't reply, and block the sender. If it claims to be your carrier or bank, contact them through the official app or the number on your card.",
  );
  lines.push("Reply 'ask Link' (or any drone) to hear one specialist out.");
  return lines.join("\n");
}

/** A single drone answers a follow-up, grounded in the last analysis. */
export function droneAnswer(
  drone: DroneInfo,
  analysis: Analysis | null,
  question: string,
): string {
  const parts: string[] = [`${drone.label} here — ${drone.specialty}.`];
  if (analysis) {
    const mine = analysis.findings.filter((f) => f.drone === drone.id);
    const pts = pointsFor(analysis, drone.id);
    if (pts > 0) {
      parts.push(
        `On the last message I flagged ${pts} risk points: ` +
          mine
            .filter((f) => f.points > 0)
            .map((f) => `${f.title} — ${f.detail}`)
            .join(" "),
      );
    } else {
      parts.push(
        `On the last message I found nothing: ${mine[0]?.detail ?? "all clear on my check."}`,
      );
    }
  }
  if (/safe|what do i do|should i|next/i.test(question)) {
    parts.push(
      "Safest move: stop, don't tap anything in the message, and reach the company through its official app or the number on your card.",
    );
  }
  parts.push(`My rule of thumb: ${drone.lesson}`);
  return parts.join("\n");
}

export const HELP_TEXT = [
  "🛡️ This is the Swat fleet line — six scam-check drones on Photon.",
  "",
  "Text me any suspicious message and the fleet scans it. If you know the",
  "number or name it came from, add a first line like:",
  "from +1 872-555-0147",
  "",
  "Commands:",
  "• scan <message> — run the fleet (or just paste the message)",
  "• ask Angler / Link / Scanner / Pressure / Impersonator / Swap — one drone explains",
  "• help — this message",
  "",
  "Prefer to talk? Call this number — the fleet answers voice-to-voice",
  "and will walk you through the same checks out loud.",
].join("\n");
