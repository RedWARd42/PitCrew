import { afterEach, describe, it, expect, vi } from "vitest";
import { createHmac } from "node:crypto";
import {
  parsePhotonWebhook,
  verifyPhotonSignature,
  photonBetaAdapter,
} from "./photon-beta";
import { PlantStore } from "../core/store";
const secret = `whsec_${Buffer.alloc(32, 7).toString("base64")}`;
function signed(
  raw: string,
  timestamp = String(Math.floor(Date.now() / 1000)),
) {
  const id = "delivery-test";
  const signature = createHmac("sha256", Buffer.alloc(32, 7))
    .update(`${id}.${timestamp}.${raw}`)
    .digest("base64");
  return new Headers({
    "webhook-id": id,
    "webhook-timestamp": timestamp,
    "webhook-signature": `v1,${signature}`,
  });
}
afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});
describe("Photon Beta webhook", () => {
  it("uses the verified Beta user page and message request shapes", async () => {
    vi.stubEnv("COMMS_MODE", "live");
    vi.stubEnv("PHOTON_PROJECT_ID", "pho_prj_test");
    vi.stubEnv("PHOTON_API_KEY", "");
    vi.stubEnv("PHOTON_PROJECT_SECRET", "test-project-api-key");
    vi.stubEnv("APP_URL", "https://plant.example");
    vi.stubEnv("PHOTON_PEOPLE_JSON", JSON.stringify({ dev: "+15550000001" }));
    vi.stubEnv("PHOTON_RECIPIENT_ALLOWLIST", "+15550000001");
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(
        Response.json({
          items: [{ id: "agent-user", platform: "imessage", kind: "agent" }],
        }),
      )
      .mockResolvedValueOnce(Response.json({ id: "recipient-user" }))
      .mockResolvedValueOnce(Response.json({ id: "dm-space" }))
      .mockResolvedValueOnce(Response.json({ id: "provider-message" }));
    vi.stubGlobal("fetch", fetch);
    const message = {
      id: "message-1",
      personId: "dev",
      entityId: "warning-CH-3",
      channel: "imessage" as const,
      direction: "outbound" as const,
      text: "Private plant evidence",
      status: "queued" as const,
      ts: "2026-11-08T06:00:00Z",
      providerMessageId: undefined as string | undefined,
      provider: undefined as string | undefined,
    };
    await photonBetaAdapter.send(message);
    expect(fetch).toHaveBeenCalledTimes(4);
    const body = JSON.parse(fetch.mock.calls[3][1].body);
    expect(body).toMatchObject({
      senderId: "agent-user",
      spaceId: "dm-space",
      content: { type: "text", format: "plain" },
    });
    expect(body.content.text).not.toContain("Private plant evidence");
    expect(message.providerMessageId).toBe("provider-message");
    expect(fetch.mock.calls[3][1].headers["Idempotency-Key"]).toBeTruthy();
  });
  it("checks the exact bytes, header timestamp and constant-time signature", () => {
    const raw = '{"type":"message.received"}',
      headers = signed(raw);
    expect(() => verifyPhotonSignature(raw, headers, secret)).not.toThrow();
    expect(() => verifyPhotonSignature(raw + " ", headers, secret)).toThrow();
    expect(() =>
      verifyPhotonSignature(raw, signed(raw, "1"), secret),
    ).toThrow();
  });
  it("allows a valid signature during rotation without trusting invalid signatures", () => {
    const raw = "{}",
      headers = signed(raw);
    headers.set(
      "webhook-signature",
      `v1,invalid ${headers.get("webhook-signature")}`,
    );
    expect(() => verifyPhotonSignature(raw, headers, secret)).not.toThrow();
  });
  it("rejects a signed event for another project", async () => {
    vi.stubEnv("PHOTON_WEBHOOK_SECRET", secret);
    vi.stubEnv("PHOTON_PROJECT_ID", "project-1");
    const raw = JSON.stringify({
      id: "evt-1",
      type: "message.received",
      apiVersion: "2026-07-01",
      data: { projectId: "project-other", object: { id: "message-1" } },
    });
    await expect(
      parsePhotonWebhook(
        new Request("https://plant.example/api/photon/webhook", {
          method: "POST",
          headers: signed(raw),
          body: raw,
        }),
      ),
    ).rejects.toThrow("Wrong project");
  });
  it("persists replay deduplication and only lets the current contact own a warning", async () => {
    vi.stubEnv("DEMO_MODE", "1");
    vi.stubEnv(
      "PHOTON_PEOPLE_JSON",
      JSON.stringify({ maria: "+15550000001", dev: "+15550000002" }),
    );
    vi.stubEnv("PHOTON_RECIPIENT_ALLOWLIST", "+15550000001,+15550000002");
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S1" });
    const event = {
      id: "event-1",
      type: "message.received",
      apiVersion: "2026-07-01",
      data: {
        projectId: "p1",
        object: {
          id: "message-1",
          sentBy: { handle: "+15550000001" },
          content: {
            type: "text",
            text: "own warning-CH-3 I will check pump B by 02:30.",
          },
        },
      },
    };
    await store.photonEvent(event);
    await store.photonEvent(event);
    expect(store.state.warnings[0].state).toBe("owned");
    expect(
      store.state.audit.filter((a) => a.action === "photon.event"),
    ).toHaveLength(1);
    await expect(
      store.photonEvent({
        ...event,
        id: "event-2",
        data: {
          ...event.data,
          object: { ...event.data.object, sentBy: { handle: "+15550000002" } },
        },
      }),
    ).rejects.toThrow("current owner");
    store.dispose();
  });
});
