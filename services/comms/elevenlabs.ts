import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import type { Message, PlantState } from "../../packages/contracts";
import type { DeliveryAdapter } from "./index";
import { allowedPhone } from "./contacts";

export function voiceIsLive() {
  return (
    process.env.VOICE_PROVIDER === "elevenlabs" &&
    process.env.VOICE_MODE === "live"
  );
}
const callResponse = z.object({
  success: z.boolean(),
  conversation_id: z.string().optional(),
  sip_call_id: z.string().optional(),
});
export const elevenLabsAdapter: DeliveryAdapter = {
  async send(message: Message) {
    if (!voiceIsLive() || message.channel !== "voice")
      throw new Error("ElevenLabs calls are disabled");
    const key = process.env.ELEVENLABS_API_KEY,
      agentId = process.env.ELEVENLABS_AGENT_ID,
      phoneId = process.env.ELEVENLABS_PHONE_NUMBER_ID;
    if (!key || !agentId || !phoneId)
      throw new Error(
        "ElevenLabs agent and imported SIP phone number must be configured",
      );
    const origin = new URL(process.env.APP_URL ?? "http://localhost:3000");
    if (
      origin.protocol !== "https:" ||
      ["localhost", "127.0.0.1", "[::1]"].includes(origin.hostname)
    )
      throw new Error("Voice tools need a public HTTPS APP_URL");
    const toNumber = allowedPhone(message.personId),
      token = randomBytes(32).toString("hex");
    message.callTokenHash = createHash("sha256").update(token).digest("hex");
    message.callExpiresAt = new Date(Date.now() + 3600000).toISOString();
    // One request only: an ambiguous timeout must never trigger an automatic second phone call.
    const response = await fetch(
      "https://api.elevenlabs.io/v1/convai/sip-trunk/outbound-call",
      {
        method: "POST",
        headers: { "xi-api-key": key, "Content-Type": "application/json" },
        signal: AbortSignal.timeout(15000),
        body: JSON.stringify({
          agent_id: agentId,
          agent_phone_number_id: phoneId,
          to_number: toNumber,
          conversation_initiation_client_data: {
            dynamic_variables: {
              warning_id: message.entityId,
              message_id: message.id,
              person_id: message.personId,
              briefing: message.text,
              secret__groundtruth_token: token,
            },
          },
        }),
      },
    );
    if (!response.ok)
      throw new Error(`ElevenLabs call request failed (${response.status})`);
    const result = callResponse.parse(await response.json());
    if (!result.success) throw new Error("ElevenLabs did not accept the call");
    message.provider = "elevenlabs";
    message.providerMessageId = result.conversation_id ?? result.sip_call_id;
  },
};

export const VoiceToolSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("context"), messageId: z.string() }),
  z.object({
    kind: z.literal("acknowledge"),
    messageId: z.string(),
    readback: z.string().trim().min(8).max(1000),
  }),
  z.object({
    kind: z.literal("note"),
    messageId: z.string(),
    text: z.string().trim().min(1).max(4000),
  }),
]);
export type VoiceTool = z.infer<typeof VoiceToolSchema>;
export function authorizeVoiceTool(
  state: PlantState,
  messageId: string,
  authorization: string | null,
) {
  const token = authorization?.startsWith("Bearer ")
    ? authorization.slice(7)
    : "";
  const message = state.messages.find(
    (m) => m.id === messageId && m.channel === "voice",
  );
  if (
    !token ||
    token.length > 256 ||
    !message?.callTokenHash ||
    !message.callExpiresAt ||
    Date.parse(message.callExpiresAt) < Date.now()
  )
    throw new Error("Unauthorized voice tool");
  const actual = createHash("sha256").update(token).digest(),
    expected = Buffer.from(message.callTokenHash, "hex");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected))
    throw new Error("Unauthorized voice tool");
  const warning = state.warnings.find((w) => w.id === message.entityId);
  if (
    !warning ||
    warning.ownerId !== message.personId ||
    warning.state === "resolved"
  )
    throw new Error("Call ownership is no longer current");
  return { message, warning };
}
