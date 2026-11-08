import { chromium } from "@playwright/test";
import { mkdir } from "node:fs/promises";
async function main() {
  const base = process.env.BASE_URL ?? "http://127.0.0.1:3012";
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_EXECUTABLE,
  });
  const page = await browser.newPage();
  page.setDefaultTimeout(90000);
  page.setDefaultNavigationTimeout(120000);
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await mkdir("tmp/decision-room", { recursive: true });
  try {
    await page.request.post(`${base}/api/command`, {
      data: { type: "scenario", id: "S1" },
    });
    await page.goto(base, { waitUntil: "domcontentloaded" });
    await page
      .getByRole("heading", { name: "Ahead of the incident." })
      .waitFor();
    await page
      .getByRole("link", { name: "Investigate the cause" })
      .waitFor();
    for (const width of [1440, 390, 320]) {
      await page.setViewportSize({ width, height: 1000 });
      if (
        await page.evaluate(
          () => document.documentElement.scrollWidth > innerWidth + 1,
        )
      )
        throw Error(`Overflow at ${width}`);
      await page.screenshot({
        path: `tmp/decision-room/evidence-${width}.png`,
        fullPage: true,
      });
    }
    await page.request.post(`${base}/api/command`, {
      data: { type: "scenario", id: "S2" },
    });
    await page.reload();
    await page.getByRole("tab", { name: "Maintenance rehearsal" }).click();
    await page.getByRole("button", { name: "Run rehearsal" }).click();
    await page
      .getByText("HOLD · Last source at risk", { exact: true })
      .waitFor();
    await page.waitForTimeout(5500);
    if (
      !(await page
        .getByText("HOLD · Last source at risk", { exact: true })
        .isVisible())
    )
      throw Error("Rehearsal disappeared on polling");
    await page.setViewportSize({ width: 1440, height: 1100 });
    await page.screenshot({
      path: "tmp/decision-room/rehearsal-1440.png",
      fullPage: true,
    });
    await page.request.post(`${base}/api/command`, {
      data: { type: "scenario", id: "S3" },
    });
    await page.reload({ waitUntil: "domcontentloaded" });
    await page.locator(".incident-banner").waitFor();
    if (errors.length) throw Error(errors.join("\n"));
    await page.request.post(`${base}/api/command`, {
      data: { type: "scenario", id: "S1" },
    });
    console.log(
      "PASS: desktop/mobile evidence, no overflow at 1440/390/320, HOLD rehearsal, poll stability, no browser errors.",
    );
  } finally {
    await browser.close();
  }
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
