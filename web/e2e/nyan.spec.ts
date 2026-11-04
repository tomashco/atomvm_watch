import { test, expect, type Page } from "@playwright/test";

// examples/nyan (a sprite and rainbow pushed by avm_scene every 50 ms, drawn by m5_scene) running in
// the real AtomVM wasm VM. Rotation 1 (240x135 landscape): logical (x, y) is native (134 - y, x).
const lp = (page: Page, x: number, y: number) =>
  page.evaluate(([x, y]) => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    return Array.from(c.getContext("2d")!.getImageData(134 - y, x, 1, 1).data).join(",");
  }, [x, y] as const);

const boxHas = (page: Page, x0: number, y0: number, x1: number, y1: number, rgba: string) =>
  page.evaluate(([x0, y0, x1, y1, rgba]) => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    const ctx = c.getContext("2d")!;
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++)
      if (Array.from(ctx.getImageData(134 - y, x, 1, 1).data).join(",") === rgba) return true;
    return false;
  }, [x0, y0, x1, y1, rgba] as const);

const snapshot = (page: Page) =>
  page.evaluate(() => (document.getElementById("screen") as HTMLCanvasElement).toDataURL());

test("nyan: animates, A pauses and resumes", async ({ page }) => {
  await page.goto("/?avm=fixtures/nyan.avm");

  // Background (0x003366) and the hint text at the bottom (0x7090C0).
  await expect.poll(() => lp(page, 236, 100), { timeout: 30_000 }).toBe("0,51,102,255");
  await expect.poll(() => boxHas(page, 4, 124, 120, 132, "112,144,192,255"), { timeout: 10_000 }).toBe(true);

  // The cat flies: frames keep changing.
  const first = await snapshot(page);
  await expect.poll(() => snapshot(page), { timeout: 10_000 }).not.toBe(first);

  // A pauses: nothing is pushed, so the screen holds still.
  await page.click('[data-btn="a"]', { delay: 150 });
  await page.waitForTimeout(500);
  const paused = await snapshot(page);
  await page.waitForTimeout(1000);
  expect(await snapshot(page)).toBe(paused);

  // A again resumes.
  await page.click('[data-btn="a"]', { delay: 150 });
  await expect.poll(() => snapshot(page), { timeout: 10_000 }).not.toBe(paused);
});
