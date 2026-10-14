import { test, expect, type Page } from "@playwright/test";

// examples/scenes (avm_scene scenes drawn by m5_scene) running in the real AtomVM wasm VM.
// The app runs at rotation 1 (240x135 landscape). The canvas is the native 135x240 framebuffer:
// logical (x, y) is native (134 - y, x). Alpha is included so a never-drawn canvas can't pass.
const lp = (page: Page, x: number, y: number) =>
  page.evaluate(([x, y]) => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    return Array.from(c.getContext("2d")!.getImageData(134 - y, x, 1, 1).data).join(",");
  }, [x, y] as const);

const BG = "16,24,40,255";
const WHITE = "255,255,255,255";
const press = (page: Page, btn: "a" | "b", ms = 150) => page.click(`[data-btn="${btn}"]`, { delay: ms });

// True when a logical box has at least one pixel of the given colour.
const boxHas = (page: Page, x0: number, y0: number, x1: number, y1: number, rgba: string) =>
  page.evaluate(([x0, y0, x1, y1, rgba]) => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    const ctx = c.getContext("2d")!;
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++)
      if (Array.from(ctx.getImageData(134 - y, x, 1, 1).data).join(",") === rgba) return true;
    return false;
  }, [x0, y0, x1, y1, rgba] as const);

test("scenes: menu, highlight, detail and back", async ({ page }) => {
  await page.goto("/?avm=fixtures/scenes.avm");

  // Menu: background, highlight on the first entry.
  await expect.poll(() => lp(page, 230, 125), { timeout: 30_000 }).toBe(BG);
  await expect.poll(() => lp(page, 200, 45), { timeout: 10_000 }).toBe(WHITE);
  // Icons: red and green disc centres (RGB565 byte order), a transparent corner over the highlight
  // and one over the background.
  expect(await lp(page, 19, 44)).toBe("255,0,0,255");
  expect(await lp(page, 19, 74)).toBe("0,255,0,255");
  expect(await lp(page, 12, 37)).toBe(WHITE);
  expect(await lp(page, 12, 67)).toBe(BG);
  // Inverted text: black glyph pixels inside the white highlight.
  expect(await boxHas(page, 36, 37, 96, 53, "0,0,0,255")).toBe(true);

  // A moves the highlight down; time it from the click to the redraw.
  const t0 = Date.now();
  await press(page, "a");
  await expect.poll(() => lp(page, 200, 75), { timeout: 10_000 }).toBe(WHITE);
  test.info().annotations.push({ type: "highlight move (ms)", description: String(Date.now() - t0) });
  expect(await lp(page, 200, 45)).toBe(BG);
  expect(await lp(page, 12, 37)).toBe(BG);

  // B opens the detail: cyan circle, yellow line, the menu is gone.
  await press(page, "b");
  await expect.poll(() => lp(page, 120, 60), { timeout: 10_000 }).toBe("0,255,255,255");
  expect(await lp(page, 100, 100)).toBe("255,255,0,255");
  expect(await lp(page, 200, 75)).toBe(BG);

  // B goes back; the selection is kept.
  await press(page, "b");
  await expect.poll(() => lp(page, 200, 75), { timeout: 10_000 }).toBe(WHITE);

  // Holding A (over the 500 ms hold threshold) also goes back.
  await press(page, "b");
  await expect.poll(() => lp(page, 120, 60), { timeout: 10_000 }).toBe("0,255,255,255");
  await press(page, "a", 900);
  await expect.poll(() => lp(page, 200, 75), { timeout: 10_000 }).toBe(WHITE);

  expect(await page.locator("#console").innerText()).not.toMatch(/undef|error|invalid display list/i);
});
