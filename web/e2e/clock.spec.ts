import { test, expect, type Page } from "@playwright/test";
import { fileURLToPath } from "node:url";

// Milestone-1 acceptance: examples/clock (Elixir, packed with mix atomvm.packbeam, bundling
// atomvm_m5's stub modules) runs in the real AtomVM wasm VM behind m5_emu.avm, reacts to the
// device buttons, and can be replaced by dropping another .avm.

const SMOKE_AVM = fileURLToPath(new URL("./fixtures/smoke_app.avm", import.meta.url));

// The canvas is the native 135x240 framebuffer (CSS scales it 3x); coordinates are native.
// Alpha is included so a blank (never drawn) canvas, which reads 0,0,0,0, can't pass.
const pixel = (page: Page, x: number, y: number) =>
  page.evaluate(([x, y]) => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    return Array.from(c.getContext("2d")!.getImageData(x, y, 1, 1).data).join(",");
  }, [x, y] as const);

const hasWhitePixel = (page: Page) =>
  page.evaluate(() => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    const d = c.getContext("2d")!.getImageData(0, 0, c.width, c.height).data;
    for (let i = 0; i < d.length; i += 4) if (d[i] === 255 && d[i + 1] === 255 && d[i + 2] === 255 && d[i + 3] === 255) return true;
    return false;
  });

const consoleText = (page: Page) => page.locator("#console").innerText();

// Playwright's plain click sends down and up a few ms apart; the app polls every 10 ms and
// m5_emu's button debounces for 10 ms, so hold the button long enough to be seen (ruling C10).
const press = (page: Page, btn: "a" | "b" | "pwr") => page.click(`[data-btn="${btn}"]`, { delay: 150 });

type Ev = { name: string; args: unknown[] };
const events = (page: Page) =>
  page.evaluate(() => (window as unknown as { m5emu: { events: Ev[] } }).m5emu.events.map((e) => ({ ...e })));

test("clock app boots, reacts to buttons, and can be replaced", async ({ page }) => {
  await page.goto("/?avm=fixtures/clock.avm");

  // Boot: clock screen, black background (opaque) with white digits.
  await expect.poll(() => pixel(page, 5, 5), { timeout: 30_000 }).toBe("0,0,0,255");
  await expect.poll(() => hasWhitePixel(page), { timeout: 10_000 }).toBe(true);
  expect(await consoleText(page)).not.toMatch(/undef|error/i);

  // Record every display command from here on, to read the about screen's text.
  await page.evaluate(() => {
    const w = window as unknown as { m5emu: { exec(c: unknown[]): void }; __cmds: unknown[] };
    w.__cmds = [];
    const exec = w.m5emu.exec;
    w.m5emu.exec = (cmds) => { w.__cmds.push(...cmds); exec(cmds); };
  });

  // A -> "buttons" screen, background 0x102040.
  await press(page, "a");
  await expect.poll(() => pixel(page, 5, 5), { timeout: 10_000 }).toBe("16,32,64,255");

  // B -> {tone, 1800, 80, _} reaches the page, the LED turns on, and the screen redraws the LED
  // square red. It is at logical (200,100)-(230,130) at rotation 1; logical (x, y) is native
  // (134 - y, x), so logical (215, 115) is native (19, 215).
  expect((await events(page)).filter((e) => e.name === "tone")).toHaveLength(0);
  await press(page, "b");
  await expect.poll(async () => (await events(page)).filter((e) => e.name === "tone"), { timeout: 10_000 })
    .toEqual([{ name: "tone", args: [1800, 80, expect.any(Number)] }]);
  await expect(page.locator("#led")).toHaveClass(/\bon\b/);
  await expect.poll(() => pixel(page, 19, 215), { timeout: 10_000 }).toBe("255,0,0,255");

  // A -> "about" screen, background 0x203010, showing the board from m5:get_board(). This is
  // m5_emu's m5 (the app pack bundles atomvm_m5's stub m5, which must be shadowed).
  await press(page, "a");
  await expect.poll(() => pixel(page, 5, 5), { timeout: 10_000 }).toBe("32,48,16,255");
  await expect.poll(() => page.evaluate(() => JSON.stringify((window as unknown as { __cmds: unknown[] }).__cmds)))
    .toContain("board: stick_cplus2");

  // Replace: choosing another .avm saves it and reloads the page, which boots the new app.
  await page.setInputFiles("#file", SMOKE_AVM);
  await page.waitForURL((u) => !u.search.includes("avm="));
  await expect(page.locator("#app-name")).toHaveText("smoke_app.avm");
  await expect.poll(() => consoleText(page), { timeout: 30_000 }).toContain("SMOKE board stick_cplus2 135x240");
  // smoke_app fills a red rect at (10,20) 30x40, rotation 0.
  await expect.poll(() => pixel(page, 20, 40), { timeout: 10_000 }).toBe("255,0,0,255");
});
