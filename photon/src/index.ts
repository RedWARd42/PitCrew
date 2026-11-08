/**
 * Swat Fleet Line — the drone fleet as a Photon 2.0 (Spectrum) agent.
 *
 * One agent loop serves every channel Photon connects: iMessage today,
 * plus whatever else the project enables in the dashboard (SMS/RCS,
 * WhatsApp, Telegram…). People text the fleet's number a suspicious
 * message; the drones scan it and answer in the same conversation.
 * Voice-to-voice runs on the same number through a Voice profile over
 * SIP — see voice/ and src/voice-config.ts.
 *
 * Credentials come from the environment (SPECTRUM_PROJECT_ID /
 * SPECTRUM_PROJECT_SECRET), exactly as the Spectrum docs specify.
 * With no project credentials, the terminal provider runs instead so
 * the loop can be tried locally with zero setup.
 */
import { Spectrum } from "spectrum-ts";
import { imessage } from "spectrum-ts/providers/imessage";
import { terminal } from "spectrum-ts/providers/terminal";
import {
  HELP_TEXT,
  analyzeMessage,
  droneAnswer,
  droneByName,
  formatAnalysis,
  type Analysis,
} from "./fleet.js";

interface SpaceState {
  lastBody?: string;
  lastSender?: string;
  lastAnalysis?: Analysis;
}

const spaces = new Map<string, SpaceState>();

const hasProject = Boolean(
  process.env.SPECTRUM_PROJECT_ID && process.env.SPECTRUM_PROJECT_SECRET,
);
const useTerminal = process.env.PHOTON_TERMINAL === "1" || !hasProject;

const providers = [];
if (hasProject) providers.push(imessage.config());
if (useTerminal) providers.push(terminal.config());

if (!hasProject) {
  console.log(
    "[swat] No SPECTRUM_PROJECT_ID / SPECTRUM_PROJECT_SECRET set — " +
      "running the terminal provider only. Create a project at " +
      "app.photon.codes and copy .env.example to .env to go live on iMessage.",
  );
}

const app = await Spectrum({ providers });
console.log(
  `[swat] Fleet line live on: ${hasProject ? "iMessage" : ""}` +
    `${hasProject && useTerminal ? " + " : ""}${useTerminal ? "terminal" : ""}`,
);

for await (const [space, message] of app.messages) {
  // Only answer inbound human messages, and only text content.
  const msg = message as unknown as {
    direction?: string;
    platform?: string;
    content?: { type?: string; text?: string };
    react?: (emoji: string) => Promise<void>;
    reply?: (text: string) => Promise<void>;
  };
  if (msg.direction && msg.direction !== "inbound") continue;
  const text = msg.content?.text?.trim();
  if (!text) continue;

  const spaceKey =
    (space as unknown as { id?: string }).id ??
    `${msg.platform ?? "unknown"}-default`;
  const state = spaces.get(spaceKey) ?? {};
  spaces.set(spaceKey, state);

  try {
    await msg.react?.("🛡️");
  } catch {
    // Reactions are a nicety, not supported on every platform.
  }

  const reply = async (body: string) => {
    const send = async () => {
      if (msg.reply) await msg.reply(body);
      else await space.send(body);
    };
    try {
      await space.responding(send);
    } catch {
      await send();
    }
  };

  const lower = text.toLowerCase();

  // --- ask a specific drone -------------------------------------------
  const askMatch = /^(?:ask\s+)?(angler|link|scanner|pressure|impersonator|swap)\b[:,]?\s*(.*)$/i.exec(
    text,
  );
  if (askMatch && state.lastAnalysis) {
    const drone = droneByName(askMatch[1])!;
    await reply(droneAnswer(drone, state.lastAnalysis, askMatch[2] ?? ""));
    continue;
  }
  if (askMatch) {
    const drone = droneByName(askMatch[1])!;
    await reply(
      `${drone.label} here — ${drone.specialty}. Send me a suspicious ` +
        `message first and I'll show you my check on it. My rule of ` +
        `thumb: ${drone.lesson}`,
    );
    continue;
  }

  // --- greetings / help -------------------------------------------------
  if (/^(hi|hello|hey|help|start|menu)\b/i.test(lower) && text.length < 30) {
    await reply(HELP_TEXT);
    continue;
  }

  // --- "from +1 …" supplies the sender for the previous message --------
  const fromOnly = /^from\s+(.+)$/is.exec(text);
  if (fromOnly && state.lastBody && !/\n/.test(text)) {
    state.lastSender = fromOnly[1].trim();
    state.lastAnalysis = analyzeMessage(state.lastSender, state.lastBody);
    await reply(
      `Re-ran the fleet with sender ${state.lastSender}:\n\n` +
        formatAnalysis(state.lastAnalysis),
    );
    continue;
  }

  // --- scan a message ----------------------------------------------------
  let sender = "";
  let body = text.replace(/^scan\s*[:\-]?\s*/i, "");
  const fromLine = /^from\s+(.+)\n([\s\S]+)$/i.exec(body);
  if (fromLine) {
    sender = fromLine[1].trim();
    body = fromLine[2].trim();
  }
  if (body.length < 12) {
    await reply(
      "Send me the suspicious message itself (paste the whole thing) " +
        "and the fleet will scan it. Reply 'help' for details.",
    );
    continue;
  }
  state.lastBody = body;
  state.lastSender = sender;
  state.lastAnalysis = analyzeMessage(sender, body);
  await reply(formatAnalysis(state.lastAnalysis));
}
