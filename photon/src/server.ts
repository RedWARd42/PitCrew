import { makeHandler } from "./handler";
import { makeProvider } from "./provider";

const handler = makeHandler();
const provider = await makeProvider();
const KEY = process.env.SWARM_KEY ?? "dev-key";

Bun.serve({
  port: Number(process.env.PORT ?? 8787),
  hostname: "127.0.0.1",
  async fetch(req) {
    const u = new URL(req.url);
    if (u.pathname === "/healthz") return Response.json({ ok: true, provider: process.env.PHOTON_PROVIDER ?? "terminal" });
    if (u.pathname !== "/internal/guardian-alert" || req.method !== "POST") return new Response("not found", { status: 404 });
    if (req.headers.get("X-Swarm-Key") !== KEY) return new Response("unauthorized", { status: 401 });
    const b: any = await req.json().catch(() => null);
    if (!b || typeof b.to !== "string" || typeof b.userAlias !== "string" || typeof b.categoryLabel !== "string" || typeof b.riskScore !== "number")
      return new Response("bad body", { status: 400 });
    await provider.send(b.to, handler.addGuardianAlert(b.to, b));
    return Response.json({ sent: true });
  },
});
console.log(`photon listening on :${process.env.PORT ?? 8787} (provider=${process.env.PHOTON_PROVIDER ?? "terminal"})`);
await provider.run(handler.onMessage);
