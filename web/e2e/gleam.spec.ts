import { test, expect, type Page } from "@playwright/test";

// The Gleam examples (examples/gleam_hello, examples/gleam_scenes) running in the real AtomVM wasm
// VM, packed by scripts/build-gleam-example.sh. Both run at rotation 1 (240x135 landscape); the
// canvas is the native 135x240 framebuffer, so logical (x, y) is native (134 - y, x).
const lp = (page: Page, x: number, y: number) =>
  page.evaluate(([x, y]) => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    return Array.from(c.getContext("2d")!.getImageData(134 - y, x, 1, 1).data).join(",");
  }, [x, y] as const);

const press = (page: Page, btn: "a" | "b", ms = 150) => page.click(`[data-btn="${btn}"]`, { delay: ms });

const PINK = "255,175,243,255";

// True when a logical box has at least one pixel of the given colour.
const boxHas = (page: Page, x0: number, y0: number, x1: number, y1: number, rgba: string) =>
  page.evaluate(([x0, y0, x1, y1, rgba]) => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    const ctx = c.getContext("2d")!;
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++)
      if (Array.from(ctx.getImageData(134 - y, x, 1, 1).data).join(",") === rgba) return true;
    return false;
  }, [x0, y0, x1, y1, rgba] as const);

// A digit's glyph pixels are background-coloured inside the pink badge (text drawn on pink).
const badgeText = (page: Page) => boxHas(page, 80, 54, 160, 85, "30,30,46,255");

test("gleam_hello: counter drawn with m5_display", async ({ page }) => {
  const errors: string[] = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  await page.goto("/?avm=fixtures/gleam_hello.avm");

  // Background, the pink badge around the count, and the count's glyphs on it.
  await expect.poll(() => lp(page, 5, 130), { timeout: 30_000 }).toBe("30,30,46,255");
  await expect.poll(() => lp(page, 75, 50), { timeout: 10_000 }).toBe(PINK);
  expect(await badgeText(page)).toBe(true);
  // The title is pink text on the background.
  expect(await boxHas(page, 30, 12, 210, 28, PINK)).toBe(true);

  // A redraws the count: the glyph pixels change. B resets and beeps.
  const snapshot = () => page.evaluate(() => (document.getElementById("screen") as HTMLCanvasElement).toDataURL());
  const before = await snapshot();
  await press(page, "a");
  await expect.poll(snapshot, { timeout: 10_000 }).not.toBe(before);
  await press(page, "b");
  await expect.poll(snapshot, { timeout: 10_000 }).toBe(before);
  const tones = await page.evaluate(() =>
    (window as unknown as { m5emu: { events: { name: string; args: unknown[] }[] } }).m5emu.events
      .filter((e) => e.name === "tone").length);
  expect(tones).toBeGreaterThan(0);
  expect(errors.filter((e) => /undef|badarg|crash/i.test(e))).toEqual([]);
});

test("gleam_scenes: typed display list through avm_scene and m5_scene", async ({ page }) => {
  await page.goto("/?avm=fixtures/gleam_scenes.avm");

  const BG = "16,24,40,255";
  const WHITE = "255,255,255,255";
  const EMPTY = "58,63,75,255";

  // Swatches (pink, cyan, yellow), the white frame around the first, the empty circle.
  await expect.poll(() => lp(page, 30, 64), { timeout: 30_000 }).toBe(PINK);
  expect(await lp(page, 80, 64)).toBe("0,255,255,255");
  expect(await lp(page, 130, 64)).toBe("255,255,0,255");
  expect(await lp(page, 8, 64)).toBe(WHITE);
  expect(await lp(page, 58, 64)).toBe(BG);
  expect(await lp(page, 196, 64)).toBe(EMPTY);
  expect(await boxHas(page, 8, 6, 160, 22, PINK)).toBe(true);

  // A moves the frame to the cyan swatch; B paints the circle cyan.
  await press(page, "a");
  await expect.poll(() => lp(page, 58, 64), { timeout: 10_000 }).toBe(WHITE);
  expect(await lp(page, 8, 64)).toBe(BG);
  await press(page, "b");
  await expect.poll(() => lp(page, 196, 64), { timeout: 10_000 }).toBe("0,255,255,255");

  // Holding A (over the 500 ms hold threshold) resets the circle and the selection.
  await press(page, "a", 900);
  await expect.poll(() => lp(page, 196, 64), { timeout: 10_000 }).toBe(EMPTY);
  expect(await lp(page, 8, 64)).toBe(WHITE);
});
