import { initializeStore } from "../../../../../../services/core/store";
import { VoiceToolSchema } from "../../../../../../services/comms/elevenlabs";
export const runtime = "nodejs";
export async function POST(request: Request) {
  const input = VoiceToolSchema.safeParse(
    await request.json().catch(() => null),
  );
  if (!input.success)
    return Response.json(
      { error: "Invalid voice tool request" },
      { status: 400 },
    );
  try {
    const store = await initializeStore();
    return Response.json(
      await store.voiceTool(input.data, request.headers.get("authorization")),
    );
  } catch {
    return Response.json(
      { error: "Voice tool authorization or state transition failed" },
      { status: 403 },
    );
  }
}
