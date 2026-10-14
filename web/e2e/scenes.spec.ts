import { test, expect, type Page } from "@playwright/test";

// examples/scenes (avm_scene scenes drawn by m5_scene) running in the real AtomVM wasm VM.
// The app runs at rotation 1 (240x135 landscape). The canvas is the native 135x240 framebuffer:
// logical (x, y) is native (134 - y, x). Alpha is included so a never-drawn canvas can't pass.
const lp = (page: Page, x: number, y: number) =>
  page.evaluate(([x, y]) => {
    const c = document.getElementById("screen") as HTMLCanvasElement;
    return Array.from(c.getContext("2d")!.getImageData(134 - y, x, 1, 1).data).join(",");
  }, [x, y] as const);

test("avm_scene pushes a display list", async ({ page }) => {
  await page.goto("/?avm=fixtures/scenes.avm");
  await expect.poll(() => lp(page, 20, 20), { timeout: 30_000 }).toBe("0,255,0,255");
  expect(await page.locator("#console").innerText()).not.toMatch(/undef|error/i);
});
