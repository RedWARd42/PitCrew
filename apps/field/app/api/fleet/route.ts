import { FleetCommandSchema } from "../../../../../packages/contracts/fleet";
import { getFleetStore } from "../../../../../services/core/fleet";
export const dynamic = "force-dynamic";
export async function GET() {
  return Response.json(getFleetStore().snapshot(), {
    headers: { "Cache-Control": "no-store" },
  });
}
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const command = FleetCommandSchema.safeParse(body);
  if (!command.success)
    return Response.json(
      { error: "Invalid fleet command", details: command.error.flatten() },
      { status: 400 },
    );
  try {
    return Response.json(await getFleetStore().command(command.data), {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    return Response.json(
      {
        error: error instanceof Error ? error.message : "Fleet command failed",
      },
      { status: 409 },
    );
  }
}
