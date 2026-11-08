import { test, expect } from "@playwright/test";

test.use({ viewport: { width: 390, height: 844 } });
test("technician records an inspection and keeps the warning owned", async ({
  page,
  request,
}) => {
  await request.post("/api/command", { data: { type: "scenario", id: "S1" } });
  await page.goto("/rounds");
  await page
    .getByRole("link", { name: "Start inspection", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Evidence reviewed · take a reading" })
    .click();
  await page.getByRole("textbox", { name: "Inspection reading" }).fill("5.6");
  await page.getByRole("button", { name: "Save reading and continue" }).click();
  await page
    .getByRole("textbox", { name: "Inspection observation" })
    .fill(
      "Pump B is rattling louder than yesterday. Check bearing this shift.",
    );
  await page
    .getByRole("button", { name: "Save observation", exact: true })
    .click();
  await page.getByRole('button',{name:'Take this follow-up'}).click();
  await page
    .getByRole("button", { name: "Review the inspection record" })
    .click();
  await page
    .getByRole("button", { name: "Record inspection", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "Chiller 3 inspection recorded." }),
  ).toBeVisible();
  const state = await (await request.get("/api/state")).json();
  expect(
    state.audit.some(
      (entry: { action: string }) => entry.action === "inspection.completed",
    ),
  ).toBeTruthy();
  expect(
    state.warnings.find(
      (warning: { assetId: string }) => warning.assetId === "CH-3",
    ).state,
  ).toBe("owned");
});

test("critical procedure holds and requires a written override", async ({
  page,
  request,
}) => {
  await request.post("/api/command", { data: { type: "scenario", id: "S2" } });
  await page.goto("/procedures?procedure=MOP-UPS&asset=PDU-4");
  await expect(page.locator(".verdict")).toContainText("HOLD");
  await expect(
    page.getByRole("button", { name: "Confirm step complete" }),
  ).toBeDisabled();
  await page.getByRole("button", { name: "Override with reason" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Record override and continue" }),
  ).toBeDisabled();
});

test("task-led mobile pages stay within the viewport", async ({
  page,
  request,
}) => {
  await request.post("/api/command", { data: { type: "scenario", id: "S1" } });
  for (const path of [
    "/",
    "/start",
    "/rounds",
    "/inspect/CH-3",
    "/a/CH-3",
    "/handover",
    "/presenter",
    "/phone",
    "/traces",
    "/_director",
    "/tags",
  ]) {
    await page.goto(path);
    await expect(page.locator("h1")).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBeTruthy();
  }
});
