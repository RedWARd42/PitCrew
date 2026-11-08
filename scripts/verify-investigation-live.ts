import { writeFile, mkdir } from "node:fs/promises";
import { PlantStore } from "../services/core/store";
import { planDiagnostic } from "../services/agents/diagnostic-planner";
import { answerInvestigation } from "../services/core/investigation";

/** Explicit, opt-in live rehearsal. Sends only the seeded S1 fixture to NVIDIA. */
async function main() {
  process.loadEnvFile(".env");
  const store = new PlantStore();
  await store.command({ type: "scenario", id: "S1" });
  await store.command({
    type: "investigate",
    assetId: "CH-3",
    useModel: false,
  });
  let record = { ...store.state.investigations[0], useModel: true };
  const turns = [];
  for (let turn = 0; turn < 4; turn++) {
    record = await planDiagnostic(store.state, record);
    turns.push(structuredClone(record));
    console.log(
      JSON.stringify({
        turn,
        mode: record.mode,
        model: record.model,
        nextCheck: record.nextCheck,
        calls: record.calls.map((c) => c.tool),
        guidance: record.guidance,
      }),
    );
    if (record.mode !== "live")
      throw Error(
        "Live Nemotron rehearsal did not complete; see the labeled fallback above.",
      );
    if (!record.nextCheck) break;
    record = answerInvestigation(
      record,
      record.nextCheck === "physical_check"
        ? { checkId: "physical_check", condition: "abnormal" }
        : { checkId: record.nextCheck, value: 5.5 },
      record.revision,
      store.state.clock,
    );
  }
  await mkdir("tmp/decision-room", { recursive: true });
  await writeFile(
    "tmp/decision-room/nemotron-live.json",
    JSON.stringify(turns, null, 2),
  );
  if (record.status !== "review")
    throw Error("Investigation did not reach review");
  console.log("PASS: live Nemotron evidence tools and adaptive field loop.");
}
main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exitCode = 1;
});
