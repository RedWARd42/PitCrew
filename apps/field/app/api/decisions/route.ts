import { z } from "zod";
import { initializeStore } from "../../../../../services/core/store";
import {
  decisionBrief,
  rehearse,
} from "../../../../../services/core/decisions";
export const dynamic = "force-dynamic";
export async function GET() {
  const store = await initializeStore();
  return Response.json(decisionBrief(store.state), {
    headers: { "Cache-Control": "no-store" },
  });
}
const Input = z
  .object({
    type: z.enum(["open_breaker", "bypass", "stop"]),
    target: z.string().min(1).max(100),
  })
  .strict();
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const parsed = Input.safeParse(body);
  if (!parsed.success)
    return Response.json(
      { error: "Choose a supported action and equipment" },
      { status: 400 },
    );
  const store = await initializeStore();
  try {
    return Response.json(rehearse(store.state, parsed.data), {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    return Response.json(
      {
        error: error instanceof Error ? error.message : "Rehearsal unavailable",
      },
      { status: 422 },
    );
  }
}
