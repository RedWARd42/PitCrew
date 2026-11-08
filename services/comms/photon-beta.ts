import { createHmac, timingSafeEqual, createHash } from "node:crypto";
import { z } from "zod";
import type { DeliveryAdapter } from "./index";
import { allowedPhone } from "./contacts";

export const PhotonEventSchema = z
  .object({
    id: z.string().min(1).max(200),
    type: z.string().max(100),
    apiVersion: z.string(),
    data: z
      .object({
        projectId: z.string(),
        object: z
          .object({
            id: z.string(),
            sentBy: z.object({ handle: z.string() }).passthrough().optional(),
            content: z
              .object({ type: z.string(), text: z.string().optional() })
              .passthrough()
              .optional(),
          })
          .passthrough(),
      })
      .passthrough(),
  })
  .passthrough();
export type PhotonEvent = z.infer<typeof PhotonEventSchema>;
export function verifyPhotonSignature(
  raw: string,
  headers: Headers,
  secret: string,
  now = Date.now(),
) {
  const id = headers.get("webhook-id"),
    timestamp = headers.get("webhook-timestamp"),
    signature = headers.get("webhook-signature");
  if (
    !id ||
    !timestamp ||
    !signature ||
    !/^\d+$/.test(timestamp) ||
    Math.abs(now / 1000 - Number(timestamp)) > 300
  )
    throw new Error("Invalid webhook signature");
  if (!secret.startsWith("whsec_"))
    throw new Error("Photon Beta requires its destination signing secret");
  const key = Buffer.from(secret.slice(6), "base64");
  if (key.length < 16) throw new Error("Invalid webhook secret");
  const expected = createHmac("sha256", key)
    .update(`${id}.${timestamp}.${raw}`)
    .digest();
  const valid = signature.split(/\s+/).some((item) => {
    const [version, encoded] = item.split(",");
    if (version !== "v1" || !encoded) return false;
    const actual = Buffer.from(encoded, "base64");
    return (
      actual.length === expected.length && timingSafeEqual(actual, expected)
    );
  });
  if (!valid) throw new Error("Invalid webhook signature");
}
export async function parsePhotonWebhook(request: Request) {
  const secret = process.env.PHOTON_WEBHOOK_SECRET;
  if (!secret) throw new Error("Webhook is not configured");
  if (Number(request.headers.get("content-length") ?? 0) > 2 * 1024 * 1024)
    throw new Error("Webhook too large");
  const reader = request.body?.getReader();
  if (!reader) throw new Error("Missing body");
  let size = 0;
  const chunks: Uint8Array[] = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > 2 * 1024 * 1024) {
      await reader.cancel();
      throw new Error("Webhook too large");
    }
    chunks.push(value);
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  verifyPhotonSignature(raw, request.headers, secret);
  const event = PhotonEventSchema.parse(JSON.parse(raw));
  if (event.data.projectId !== process.env.PHOTON_PROJECT_ID)
    throw new Error("Wrong project");
  if (
    event.apiVersion !==
    (process.env.PHOTON_WEBHOOK_API_VERSION ?? "2026-07-01")
  )
    throw new Error("Unsupported webhook API version");
  return event;
}
const userSchema = z.object({
  id: z.string(),
  platform: z.string(),
  kind: z.string(),
});
export const photonBetaAdapter: DeliveryAdapter = {
  async send(message) {
    if (process.env.COMMS_MODE !== "live")
      throw new Error("Photon messaging is disabled");
    const project = process.env.PHOTON_PROJECT_ID,
      key = process.env.PHOTON_API_KEY?.trim() || process.env.PHOTON_PROJECT_SECRET?.trim();
    if (!project?.startsWith("pho_prj_") || !key)
      throw new Error("Photon Beta credentials missing");
    const phone = allowedPhone(message.personId),
      origin = new URL(process.env.APP_URL ?? "http://localhost:3000");
    if (
      origin.protocol !== "https:" ||
      ["localhost", "127.0.0.1", "[::1]"].includes(origin.hostname)
    )
      throw new Error("Live messaging requires a public HTTPS app");
    const base = `https://api.photon.codes/v1/projects/${encodeURIComponent(project)}`;
    const call = async (path: string, body?: unknown) => {
      const encoded = body === undefined ? undefined : JSON.stringify(body);
      const idempotency = createHash("sha256")
        .update(
          `${project}:${message.id}:${message.ts}:${path}:${encoded ?? ""}`,
        )
        .digest("hex");
      const response = await fetch(`${base}${path}`, {
        method: encoded ? "POST" : "GET",
        headers: {
          Authorization: `Bearer ${key}`,
          "Content-Type": "application/json",
          ...(encoded ? { "Idempotency-Key": idempotency } : {}),
        },
        body: encoded,
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok)
        throw new Error(`Photon request failed (${response.status})`);
      return response.json();
    };
    const users = z
      .object({ items: z.array(userSchema) })
      .parse(await call("/users?platform=imessage&pageSize=100"));
    const agents = users.items.filter(
      (u) => u.platform === "imessage" && u.kind === "agent",
    );
    const sender =
      process.env.PHOTON_SENDER_USER_ID ??
      (agents.length === 1 ? agents[0].id : undefined);
    if (!sender || !agents.some((u) => u.id === sender))
      throw new Error(
        "Select a project-owned iMessage agent with PHOTON_SENDER_USER_ID",
      );
    const recipient = z
      .object({ id: z.string() })
      .parse(await call("/users", { platform: "imessage", handle: phone }));
    const space = z
      .object({ id: z.string() })
      .parse(
        await call("/spaces", {
          platform: "imessage",
          participantIds: [sender, recipient.id],
        }),
      );
    const url = new URL(
      message.entityId === "handover"
        ? "/handover"
        : `/warnings/${encodeURIComponent(message.entityId)}`,
      origin,
    );
    const sent = z
      .object({ id: z.string() })
      .parse(
        await call("/messages", {
          senderId: sender,
          spaceId: space.id,
          content: {
            type: "text",
            format: "plain",
            text: `Groundtruth: an operations item needs your attention. Open the app for details and read-back: ${url}`,
          },
        }),
      );
    message.provider = "photon-beta";
    message.providerMessageId = sent.id;
  },
};
