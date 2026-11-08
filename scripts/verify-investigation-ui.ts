import { chromium } from "@playwright/test";
import { mkdir } from "node:fs/promises";
async function main() {
  const base = process.env.BASE_URL ?? "http://127.0.0.1:3012";
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_EXECUTABLE,
  });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.setDefaultTimeout(60000);
  const scenario = async (id: string) => {
    const r = await page.request.post(base + "/api/command", {
      data: { type: "scenario", id },
    });
    if (!r.ok()) throw Error(await r.text());
  };
  try {
    await scenario("S1");
    await page.goto(base + "/investigate/CH-3", {
      waitUntil: "domcontentloaded",
    });
    await page.getByRole("checkbox").uncheck();
    await page.getByRole("button", { name: "Start investigation" }).click();
    await page.getByLabel("Independent reading").fill("5.5");
    await page.getByRole("button", { name: "Submit evidence" }).click();
    await page.getByLabel("Something abnormal").check();
    await page.getByRole("button", { name: "Submit evidence" }).click();
    await page
      .getByRole("heading", { name: "Ready for technical review" })
      .waitFor();
    await page.getByRole("button", { name: "Take this follow-up" }).click();
    const snapshot = await (await page.request.get(base + "/api/state")).json();
    if (
      snapshot.warnings[0].state !== "owned" ||
      snapshot.warnings[0].readback !== ""
    )
      throw Error("One-tap acceptance failed");
    await mkdir("tmp/decision-room", { recursive: true });
    for (const width of [390, 1440, 320]) {
      await page.setViewportSize({ width, height: 1000 });
      if (
        await page.evaluate(
          () => document.documentElement.scrollWidth > innerWidth + 1,
        )
      )
        throw Error("Overflow " + width);
      await page.screenshot({
        path: `tmp/decision-room/investigation-${width}.png`,
        fullPage: true,
      });
    }
    await page.request.post(base + "/api/command", {
      data: { type: "handover" },
    });
    const handed = await (await page.request.get(base + "/api/state")).json();
    if (
      !handed.handover.some((h: { summary: string }) =>
        h.summary.includes("local_reading: 5.5"),
      )
    )
      throw Error("Evidence absent from handover");
    await scenario("S5");
    await page.goto(base + "/investigate/CRAH-1", {
      waitUntil: "domcontentloaded",
    });
    await page.getByRole("checkbox").uncheck();
    await page.getByRole("button", { name: "Start investigation" }).click();
    await page.getByLabel("Independent reading").fill("74");
    await page.getByRole("button", { name: "Submit evidence" }).click();
    await page
      .getByRole("heading", { name: "Repeat the independent measurement" })
      .waitFor();
    await page.getByLabel("Independent reading").fill("74.1");
    await page.getByRole("button", { name: "Submit evidence" }).click();
    await page.getByLabel("No abnormality observed").check();
    await page.getByRole("button", { name: "Submit evidence" }).click();
    await page
      .getByRole("heading", { name: /Two independent readings disagree/ })
      .waitFor();
    await page.reload({ waitUntil: "domcontentloaded" });
    await page
      .getByRole("heading", { name: /Two independent readings disagree/ })
      .waitFor();
    if (errors.length) throw Error(errors.join("\n"));
    await scenario("S1");
    console.log(
      "PASS: phone investigation, equipment vs sensor branches, one-tap acceptance, automatic handover, refresh persistence, 320/390/1440 layouts.",
    );
  } finally {
    await browser.close();
  }
}
main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
