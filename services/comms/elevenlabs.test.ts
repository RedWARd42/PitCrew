import { afterEach, describe, it, expect, vi } from "vitest";
import { createHash } from "node:crypto";
import { createInitialState } from "../sim";
import { PlantStore } from "../core/store";
import { elevenLabsAdapter, authorizeVoiceTool } from "./elevenlabs";
import { enqueue, flushOutbound } from "./index";

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});
function configure() {
  vi.stubEnv("VOICE_PROVIDER", "elevenlabs");
  vi.stubEnv("VOICE_MODE", "live");
  vi.stubEnv("ELEVENLABS_API_KEY", "test-api-key");
  vi.stubEnv("ELEVENLABS_AGENT_ID", "agent-test");
  vi.stubEnv("ELEVENLABS_PHONE_NUMBER_ID", "phone-test");
  vi.stubEnv("APP_URL", "https://plant.example");
  vi.stubEnv("PHOTON_PEOPLE_JSON", JSON.stringify({ dev: "+15550000001" }));
  vi.stubEnv("PHOTON_RECIPIENT_ALLOWLIST", "+15550000001");
}
describe("ElevenLabs call integration", () => {
  it("keeps calls simulated and never contacts the provider by default", async () => {
    const fetch = vi.fn();
    vi.stubGlobal("fetch", fetch);
    vi.stubEnv("VOICE_MODE", "simulated");
    const s = createInitialState();
    const m = enqueue(s, "dev", "w1", "Test", "voice");
    expect(m.status).toBe("simulated");
    await flushOutbound(s, elevenLabsAdapter);
    expect(fetch).not.toHaveBeenCalled();
  });
  it("requires recipient opt-in before sending a call", async () => {
    configure();
    vi.stubEnv("PHOTON_RECIPIENT_ALLOWLIST", "");
    const fetch = vi.fn();
    vi.stubGlobal("fetch", fetch);
    const s = createInitialState();
    await expect(
      elevenLabsAdapter.send(enqueue(s, "dev", "w1", "Test", "voice")),
    ).rejects.toThrow("opted in");
    expect(fetch).not.toHaveBeenCalled();
  });
  it("sends the documented SIP payload once with a scoped secret tool token", async () => {
    configure();
    const fetch = vi
      .fn()
      .mockResolvedValue(
        Response.json({
          success: true,
          conversation_id: "conv-1",
          sip_call_id: "sip-1",
        }),
      );
    vi.stubGlobal("fetch", fetch);
    const s = createInitialState(),
      m = enqueue(s, "dev", "w1", "Check pump B", "voice");
    await elevenLabsAdapter.send(m);
    expect(fetch).toHaveBeenCalledTimes(1);
    const [url, request] = fetch.mock.calls[0];
    expect(url).toBe(
      "https://api.elevenlabs.io/v1/convai/sip-trunk/outbound-call",
    );
    const body = JSON.parse(request.body);
    expect(body).toMatchObject({
      agent_id: "agent-test",
      agent_phone_number_id: "phone-test",
      to_number: "+15550000001",
    });
    const token =
      body.conversation_initiation_client_data.dynamic_variables
        .secret__groundtruth_token;
    expect(m.callTokenHash).toBe(
      createHash("sha256").update(token).digest("hex"),
    );
    expect(JSON.stringify(m)).not.toContain(token);
    expect(m.providerMessageId).toBe("conv-1");
  });
  it("does not retry an ambiguous transport failure or resend a failed call", async () => {
    configure();
    const fetch = vi.fn().mockRejectedValue(new Error("timeout"));
    vi.stubGlobal("fetch", fetch);
    const s = createInitialState(),
      m = enqueue(s, "dev", "w1", "Test", "voice");
    const checkpoint = vi.fn(async () => {});
    await flushOutbound(s, elevenLabsAdapter, checkpoint);
    expect(m.status).toBe("failed");
    await flushOutbound(s, elevenLabsAdapter, checkpoint);
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(checkpoint).toHaveBeenCalledTimes(2);
  });
  it("records sending before contacting a provider and never resends crash-ambiguous records", async () => {
    configure();
    const s = createInitialState(),
      m = enqueue(s, "dev", "w1", "Test", "voice");
    const stages: string[] = [];
    await flushOutbound(
      s,
      {
        send: async () => {
          stages.push(m.status);
        },
      },
      async () => {
        stages.push(m.status);
      },
    );
    expect(stages).toEqual(["sending", "sending", "sent"]);
    m.status = "sending";
    const send = vi.fn();
    await flushOutbound(s, { send });
    expect(send).not.toHaveBeenCalled();
  });
  it("uses real call text only when explicitly enabled", async () => {
    configure();
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S1" });
    await store.command({ type: "step", seconds: 45 });
    const m = store.state.messages.find((m) => m.channel === "voice")!;
    expect(m.status).toBe("queued");
    expect(m.text).not.toMatch(/SIMULATED/);
    store.dispose();
  });
  it("binds voice tools to the current owner, warning and expiration", async () => {
    vi.stubEnv("DEMO_MODE", "1");
    const store = new PlantStore();
    await store.command({ type: "scenario", id: "S1" });
    await store.command({ type: "step", seconds: 45 });
    const m = store.state.messages.find((m) => m.channel === "voice")!;
    m.callTokenHash = createHash("sha256").update("call-token").digest("hex");
    m.callExpiresAt = new Date(Date.now() + 60000).toISOString();
    const input = {
      kind: "acknowledge" as const,
      messageId: m.id,
      readback: "I will inspect pump B by 02:30.",
    };
    await expect(store.voiceTool(input, "Bearer wrong-token")).rejects.toThrow(
      "Unauthorized",
    );
    await store.voiceTool(input, "Bearer call-token");
    expect(store.state.warnings[0].readback).toBe(input.readback);
    expect(await store.voiceTool(input, "Bearer call-token")).toMatchObject({
      duplicate: true,
    });
    store.state.messages.find((record) => record.id === m.id)!.callExpiresAt =
      new Date(0).toISOString();
    expect(() =>
      authorizeVoiceTool(store.state, m.id, "Bearer call-token"),
    ).toThrow();
    store.dispose();
  });
});
