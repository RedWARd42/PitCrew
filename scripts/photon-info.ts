import { existsSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === "object")
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [
        key,
        /secret|password|token|authorization|signingKey/i.test(key)
          ? "[REDACTED]"
          : redact(item),
      ]),
    );
  return value;
}
async function main() {
  if (existsSync(".env")) process.loadEnvFile(".env");
  const id = process.env.PHOTON_PROJECT_ID,
    key = process.env.PHOTON_API_KEY?.trim() || process.env.PHOTON_PROJECT_SECRET?.trim();
  if (!id?.startsWith("pho_prj_"))
    throw new Error(
      "This read-only inspector requires the configured Photon Beta project ID.",
    );
  if (!key)
    throw new Error("Configure a Photon project API key locally first.");
  const report: Record<string, unknown> = {
    projectId: id,
    version: "Beta 2.0",
    readOnly: true,
  };
  const get = async (path: string) => {
    const response = await fetch(
      `https://api.photon.codes/v1/projects/${encodeURIComponent(id)}${path}`,
      {
        headers: { Authorization: `Bearer ${key}` },
        signal: AbortSignal.timeout(15000),
      },
    );
    if (!response.ok) return { httpStatus: response.status };
    return redact(await response.json());
  };
  report.project = await get("");
  report.platforms = await get("/platforms");
  report.resources = await get("/platforms/resources");
  report.users = await get("/users");
  report.voiceProfile = await get("/platforms/voice/profiles/default");
  report.webhookDestinations = await get("/webhooks/destinations");
  report.apiVersions = await get("/webhooks/api-versions");
  const versionText = JSON.stringify(report.apiVersions);
  const versions = [...new Set(versionText.match(/\d{4}-\d{2}-\d{2}/g) ?? [])]
    .sort()
    .reverse();
  if (versions[0])
    report.events = await get(
      `/webhooks/event-types?apiVersion=${versions[0]}`,
    );
  const dir = resolve("data/runtime");
  await mkdir(dir, { recursive: true });
  await writeFile(
    resolve(dir, "photon-setup.json"),
    JSON.stringify(report, null, 2),
  );
  console.log(
    "Saved read-only Photon project, platform, voice, webhook and event information to data/runtime/photon-setup.json. Secret fields are redacted.",
  );
  const project = report.project as { name?: string };
  const events = report.events as { events?: { type: string }[] } | undefined;
  console.log(
    JSON.stringify(
      {
        projectName: project.name,
        projectId: id,
        apiVersions: report.apiVersions,
        events: events?.events?.map((e) => e.type),
      },
      null,
      2,
    ),
  );
}
void main().catch(() => {
  console.error(
    "Photon inspection failed. Check project API credentials and connectivity; no project configuration was changed.",
  );
  process.exitCode = 1;
});
