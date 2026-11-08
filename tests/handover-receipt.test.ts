import { test, expect } from "vitest";
import { PlantStore } from "../services/core/store";
import { receivedHandover } from "../apps/field/lib/task-flow";

test("receiving a handover stays recorded when the outgoing brief is drafted", async () => {
  process.env.DEMO_MODE = "1";
  process.env.DEMO_CACHE = "only";
  process.env.COMMS_MODE = "terminal";
  const store = new PlantStore();
  await store.command({ type: "scenario", id: "S1" });
  expect(receivedHandover(store.state)).toBe(false);
  for (const item of [...store.state.handover])
    await store.command({
      type: "confirm",
      itemId: item.id,
      readback: "I will inspect this equipment and follow through this shift.",
    });
  expect(
    store.state.audit.filter((item) => item.action === "handover.received"),
  ).toHaveLength(1);
  expect(receivedHandover(store.state)).toBe(true);
  await store.command({ type: "handover" });
  expect(store.state.handover.some((item) => !item.confirmed)).toBe(true);
  expect(receivedHandover(store.state)).toBe(true);
  await store.command({ type: "reset" });
  expect(receivedHandover(store.state)).toBe(false);
});
