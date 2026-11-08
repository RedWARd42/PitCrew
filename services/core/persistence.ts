import { StateSchema, type PlantState } from "../../packages/contracts";

// Demo always remains local. Live deployment explicitly opts in after migration.
export async function persistState(state: PlantState) {
  if (process.env.DEMO_MODE !== "0") return;
  const url = process.env.SUPABASE_URL,
    key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key)
    throw new Error("Live mode requires Supabase server credentials");
  const response = await fetch(`${url}/rest/v1/plant_snapshot`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates",
    },
    body: JSON.stringify({
      id: "dal-1",
      data: StateSchema.parse(state),
      updated_at: new Date().toISOString(),
    }),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok)
    throw new Error(`Supabase persistence failed (${response.status})`);
}
export async function loadPersistedState(): Promise<PlantState | null> {
  if (process.env.DEMO_MODE !== "0") return null;
  const url = process.env.SUPABASE_URL,
    key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key)
    throw new Error("Live mode requires Supabase server credentials");
  const response = await fetch(
    `${url}/rest/v1/plant_snapshot?id=eq.dal-1&select=data`,
    {
      headers: { apikey: key, Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(5000),
    },
  );
  if (!response.ok)
    throw new Error(`Supabase load failed (${response.status})`);
  const rows = (await response.json()) as { data: unknown }[];
  return rows[0] ? StateSchema.parse(rows[0].data) : null;
}
