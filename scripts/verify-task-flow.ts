import { chromium, type Page } from "@playwright/test";
import { mkdir, writeFile } from "node:fs/promises";
import { PlantStore } from "../services/core/store";
import { compilerSources } from "../services/agents/compiler-api";

// No credentials are loaded, and no running database or communications are used.
process.env.DEMO_MODE = "1";
process.env.DEMO_CACHE = "only";
process.env.COMMS_MODE = "terminal";
process.env.VOICE_MODE = "simulated";
const baseURL =
  process.env.PLAYWRIGHT_BASE_URL ??
  process.env.BASE_URL ??
  "http://127.0.0.1:3000";
const folder = "tmp/task-flow";
const checks: string[] = [];
const screenshots: string[] = [];

async function settle(page: Page) {
  await page.locator("h1").waitFor();
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() =>
    [...document.querySelectorAll("main,.inspection-stage")].every(
      (element) => Number(getComputedStyle(element).opacity) >= 0.99,
    ),
  );
}
async function visit(page: Page, path: string) {
  await page.goto(new URL(path, baseURL).href);
  await settle(page);
}
async function checkWidth(page: Page, label: string) {
  if (
    await page.evaluate(
      () => document.documentElement.scrollWidth > innerWidth + 1,
    )
  )
    throw Error(`Horizontal overflow: ${label}`);
  checks.push(`Viewport: ${label}`);
}
async function capture(page: Page, label: string) {
  await settle(page);
  const path = `${folder}/${label}.png`;
  await page.screenshot({ path, fullPage: true, animations: "disabled" });
  screenshots.push(path);
}
async function captureStep(page: Page, label: string) {
  for (const width of [1440, 390, 320]) {
    await page.setViewportSize({ width, height: width === 1440 ? 1100 : 844 });
    await checkWidth(page, `${label} ${width}`);
    if (width !== 320) await capture(page, `${label}-${width}`);
  }
  await page.setViewportSize({ width: 390, height: 844 });
}
async function clickDestination(page: Page, selector: string, path: string) {
  const link = page.locator(selector);
  await link.scrollIntoViewIfNeeded();
  await link.click();
  await page.waitForURL((url) => url.pathname === path);
  await settle(page);
}

async function main() {
  await mkdir(folder, { recursive: true });
  const store = new PlantStore();
  await store.command({ type: "scenario", id: "S1" });
  const browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.CHROMIUM_EXECUTABLE ??
      "C:/Program Files/Google/Chrome/Application/chrome.exe",
  });
  const errors: string[] = [];
  try {
    const page = await browser.newPage({
      viewport: { width: 1440, height: 1100 },
      serviceWorkers: "block",
    });
    page.setDefaultTimeout(15000);
    // Raw JavaScript avoids TypeScript transpiler helpers in the browser closure.
    await page.addInitScript({
      content: `Object.defineProperty(window,'EventSource',{value:class {
      constructor(){this.closed=false;}
      set onopen(handler){setTimeout(()=>{if(!this.closed)handler?.(new Event('open'));},0);}
      close(){this.closed=true;}
    }});`,
    });
    await page.route("**/api/state", (route) =>
      route.fulfill({ json: store.state }),
    );
    await page.route("**/api/events", (route) => route.abort());
    await page.route("**/api/procedures/compile", (route) =>
      route.fulfill({ json: { sources: compilerSources() } }),
    );
    await page.route("**/api/command", async (route) => {
      try {
        await route.fulfill({
          json: await store.command(route.request().postDataJSON()),
        });
      } catch (error) {
        await route.fulfill({
          status: 409,
          json: {
            error: error instanceof Error ? error.message : String(error),
          },
        });
      }
    });
    page.on("pageerror", (error) => errors.push(error.message));

    const routes = [
      ["/", "home"],
      ["/start", "start"],
      ["/rounds", "rounds"],
      ["/inspect/CH-3", "inspection"],
      ["/handover", "handover"],
      ["/presenter", "presenter"],
    ] as const;
    for (const width of [1440, 390, 320]) {
      await page.setViewportSize({
        width,
        height: width === 1440 ? 1100 : 844,
      });
      for (const [path, label] of routes) {
        await visit(page, path);
        await checkWidth(page, `${label} ${width}`);
        if (width !== 320) await capture(page, `${label}-${width}`);
        if (path === "/") {
          if (await page.locator(".shift-metrics").count())
            throw Error("Old dashboard KPI metrics remain on the task home");
          if (
            await page
              .locator(
                'nav a[href="/_director"],nav a[href="/traces"],.sidebar a[href="/_director"],.sidebar a[href="/traces"],.topbar a[href="/_director"],.topbar a[href="/traces"]',
              )
              .count()
          )
            throw Error("Presenter tools remain in technician navigation");
        }
      }
    }
    checks.push(
      "Task home replaces dashboard KPIs and omits presenter tools from technician navigation",
    );
    console.log(
      "Passed task-route rendering and viewport checks at 1440, 390, and 320px.",
    );

    await page.setViewportSize({ width: 390, height: 844 });
    await visit(page, "/start");
    const inherited = store.state.handover.length;
    for (let i = 0; i < inherited; i++) {
      await page
        .getByRole("button", { name: "Confirm with a read-back", exact: true })
        .first()
        .click();
      await page
        .getByRole("textbox", { name: "Read-back or override reason" })
        .fill(
          `I will carry forward inherited action ${i + 1} and follow its assigned deadline.`,
        );
      await page
        .getByRole("button", { name: "Confirm read-back", exact: true })
        .click();
      await page.getByRole("dialog").waitFor({ state: "hidden" });
    }
    if (
      !store.state.handover.every(
        (item) => item.confirmed && item.readback.trim(),
      )
    )
      throw Error("Inherited handover did not retain all read-backs");
    const incomingReadbacks = store.state.handover.map((item) => item.readback);
    const incomingReceipt = store.state.audit.find(
      (item) => item.action === "handover.received",
    );
    if (
      !incomingReceipt ||
      store.state.audit.filter((item) => item.action === "handover.received")
        .length !== 1
    )
      throw Error("Incoming handover receipt was not recorded exactly once");
    await page
      .getByRole("link", { name: "Begin my rounds", exact: true })
      .waitFor();
    await captureStep(page, "intake-confirmed");
    checks.push(
      `Inherited handover: ${inherited} items confirmed through read-back dialogs`,
    );

    await page
      .getByRole("link", { name: "Begin my rounds", exact: true })
      .click();
    await page.waitForURL((url) => url.pathname === "/rounds");
    await settle(page);
    const start = page.getByRole("link", {
      name: "Start inspection",
      exact: true,
    });
    if ((await start.getAttribute("href")) !== "/inspect/CH-3")
      throw Error("S1 did not prioritize the chiller inspection");
    await start.click();
    await page.waitForURL((url) => url.pathname === "/inspect/CH-3");
    await page
      .getByRole("heading", { name: "Know why you’re here.", exact: true })
      .waitFor();
    await captureStep(page, "step-1-evidence");
    await page
      .getByRole("button", {
        name: "Evidence reviewed · take a reading",
        exact: true,
      })
      .click();
    await page.getByRole("textbox", { name: "Inspection reading" }).waitFor();
    await page.getByRole("textbox", { name: "Inspection reading" }).fill("5.6");
    await captureStep(page, "step-2-reading");
    await page
      .getByRole("button", { name: "Save reading and continue", exact: true })
      .click();
    await page
      .getByRole("textbox", { name: "Inspection observation" })
      .waitFor();
    if (store.state.assets.find((asset) => asset.id === "CH-3")?.value !== 5.6)
      throw Error("Inspection reading was not saved");
    const note =
      "Pump B still rattles under load. Bearing review remains assigned for this shift.";
    await page
      .getByRole("textbox", { name: "Inspection observation" })
      .fill(note);
    await captureStep(page, "step-3-observation");
    await page
      .getByRole("button", { name: "Save observation", exact: true })
      .click();
    await page.getByRole("textbox", { name: "Inspection read-back" }).waitFor();
    if (
      !store.state.notes.some(
        (item) => item.assetId === "CH-3" && item.text === note,
      )
    )
      throw Error("Inspection observation was not saved");
    const readback =
      "I will check pump B bearing and record the follow-up by 02:30.";
    await page
      .getByRole("textbox", { name: "Inspection read-back" })
      .fill(readback);
    await captureStep(page, "step-4-ownership");
    await page
      .getByRole("button", { name: "Confirm ownership", exact: true })
      .click();
    await page
      .getByRole("button", {
        name: "Review the inspection record",
        exact: true,
      })
      .waitFor();
    await page
      .getByRole("button", {
        name: "Review the inspection record",
        exact: true,
      })
      .click();
    await page
      .getByRole("button", { name: "Record inspection", exact: true })
      .waitFor();
    if (
      await page
        .getByRole("button", { name: "Record inspection", exact: true })
        .isDisabled()
    )
      throw Error("A fully recorded inspection is still blocked");
    await captureStep(page, "step-5-review");
    await page
      .getByRole("button", { name: "Record inspection", exact: true })
      .click();
    await page
      .getByRole("heading", {
        name: "Chiller 3 inspection recorded.",
        exact: true,
      })
      .waitFor();
    const completion = store.state.audit
      .filter(
        (entry) =>
          entry.action === "inspection.completed" &&
          entry.detail.startsWith("CH-3: "),
      )
      .at(-1);
    if (!completion) throw Error("Completion audit was not recorded");
    const commitments = structuredClone(
      store.state.warnings.filter((warning) => warning.assetId === "CH-3"),
    );
    if (
      !commitments.length ||
      !commitments.every(
        (warning) => warning.state === "owned" && warning.readback === readback,
      )
    )
      throw Error(
        "Inspection cleared or failed to preserve the active owned warning",
      );
    await captureStep(page, "inspection-recorded");
    await page.reload();
    await settle(page);
    await page
      .getByRole("heading", {
        name: "Chiller 3 inspection recorded.",
        exact: true,
      })
      .waitFor();
    checks.push(
      "Guided evidence → reading → observation → ownership → review → completion; completion audit survives browser reload",
    );
    console.log(
      "Passed complete guided inspection and reload persistence; commitments remain owned and active.",
    );

    const next = page.getByRole("link", { name: /^Next stop:/ });
    const nextPath = await next.getAttribute("href");
    if (
      !nextPath ||
      nextPath === "/inspect/CH-3" ||
      !nextPath.startsWith("/inspect/")
    )
      throw Error("Next stop did not advance to another asset");
    await next.click();
    await page.waitForURL((url) => url.pathname === nextPath);
    await settle(page);
    await page
      .getByRole("heading", { name: "Know why you’re here.", exact: true })
      .waitFor();
    checks.push(`Next stop advances to ${nextPath}`);
    await visit(page, "/rounds");
    const recordedRow = page.locator('.work-list a[href="/inspect/CH-3"]');
    await recordedRow.getByText("Recorded", { exact: true }).waitFor();
    if (
      (await page
        .getByRole("link", { name: "Start inspection", exact: true })
        .getAttribute("href")) === "/inspect/CH-3"
    )
      throw Error("Rounds still offers the completed stop as next");
    await captureStep(page, "rounds-after-recording");
    checks.push("Recorded inspection remains marked in walking route");

    // Preparing the outgoing brief must not send the technician back through
    // incoming intake or discard the read-backs already received this shift.
    await store.command({ type: "handover" });
    if (!store.state.handover.some((item) => !item.confirmed))
      throw Error("Receipt test requires newly drafted outgoing items");
    if (
      store.state.audit.filter((item) => item.action === "handover.received")
        .length !== 1
    )
      throw Error("Outgoing draft duplicated the incoming receipt");
    await visit(page, "/start");
    await page
      .getByRole("heading", {
        name: "You already have the shift context.",
        exact: true,
      })
      .waitFor();
    for (const readback of incomingReadbacks)
      await page.locator("blockquote").filter({ hasText: readback }).waitFor();
    if (
      await page
        .getByRole("button", { name: "Confirm with a read-back", exact: true })
        .count()
    )
      throw Error(
        "Incoming receipt became an editable intake after outgoing draft",
      );
    if (
      (await page
        .getByRole("link", { name: "Continue my rounds", exact: true })
        .getAttribute("href")) !== "/rounds"
    )
      throw Error("Incoming receipt lost its rounds destination");
    if (
      (await page
        .getByRole("link", { name: "Review my outgoing handover", exact: true })
        .getAttribute("href")) !== "/handover"
    )
      throw Error("Incoming receipt lost its outgoing handover destination");
    await captureStep(page, "handover-received");
    await visit(page, "/");
    if (await page.locator(".intake-prompt").count())
      throw Error(
        "Home repeats incoming intake after preparing outgoing handover",
      );
    await page.locator('.shift-journey a[href="/start"].complete').waitFor();
    checks.push(
      "Incoming receipt and original read-backs survive outgoing draft; home keeps phase one complete without a repeated intake prompt",
    );
    console.log(
      "Passed durable incoming handover receipt after preparing an outgoing brief.",
    );

    await visit(page, "/presenter");
    await clickDestination(
      page,
      '.presenter-home a[href="/_director"]',
      "/_director",
    );
    await visit(page, "/presenter");
    await clickDestination(
      page,
      '.presenter-home a[href="/traces"]',
      "/traces",
    );
    checks.push(
      "Presenter workspace still links to scenario controls and agent traces",
    );

    for (const path of ["/", "/inspect/CH-3"]) {
      await visit(page, path);
      await page
        .locator('button[aria-label="Toggle light mode"]:visible')
        .first()
        .click();
      await page.waitForFunction(
        () => document.documentElement.dataset.theme === "light",
      );
      await checkWidth(page, `light ${path}`);
      await capture(
        page,
        `light-${path === "/" ? "home" : "inspection-recorded"}-390`,
      );
    }
    await page.emulateMedia({ reducedMotion: "reduce" });
    await visit(page, nextPath);
    await page
      .getByRole("button", {
        name: "Evidence reviewed · take a reading",
        exact: true,
      })
      .click();
    await page.getByRole("textbox", { name: "Inspection reading" }).waitFor();
    await capture(page, "reduced-motion-reading-390");
    if (
      !(await page.evaluate(
        () => matchMedia("(prefers-reduced-motion: reduce)").matches,
      ))
    )
      throw Error("Reduced-motion preference was not applied");
    checks.push("Light theme and reduced-motion inspection step remain usable");

    await store.command({ type: "scenario", id: "S2" });
    await visit(page, "/procedures?procedure=MOP-UPS&asset=PDU-4");
    await page.locator(".verdict.hold").waitFor();
    if (
      !(await page
        .getByRole("button", { name: "Confirm step complete", exact: true })
        .isDisabled())
    )
      throw Error("S2 HOLD gate no longer disables procedure completion");
    await checkWidth(page, "S2 HOLD 390");
    await capture(page, "procedure-hold-390");
    checks.push("Existing S2 procedure HOLD remains enforced");
    if (errors.length) throw Error(errors.join("\n"));
    await writeFile(
      `${folder}/verification.json`,
      JSON.stringify(
        {
          baseURL,
          fixture: "isolated in-memory S1/S2",
          checks,
          screenshots,
          completion,
          commitments,
          incomingReceipt,
          browserErrors: errors,
        },
        null,
        2,
      ),
    );
    console.log(
      `Passed task-led flow: ${checks.length} checks; ${screenshots.length} screenshots; no browser errors or live-data changes.`,
    );
  } finally {
    await browser.close();
  }
}
void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
