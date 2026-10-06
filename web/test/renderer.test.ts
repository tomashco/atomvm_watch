import { describe, it, expect } from "vitest";
import { M5Renderer } from "../src/renderer";
import { PNG } from "pngjs";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";

const mk = () => new M5Renderer(135, 240);
function expectGolden(r: M5Renderer, name: string) {
  const dir = new URL("./golden/", import.meta.url);
  mkdirSync(dir, { recursive: true });
  const file = new URL(`./golden/${name}.png`, import.meta.url);
  const png = new PNG({ width: r.fb.width, height: r.fb.height });
  png.data = Buffer.from(r.fb.toRGBA());
  const actual = PNG.sync.write(png);
  if (!existsSync(file) || process.env.UPDATE_GOLDENS) {
    if (process.env.CI && !process.env.UPDATE_GOLDENS) throw new Error(`missing golden ${name}.png (CI never writes goldens)`);
    writeFileSync(file, actual);
    return;
  }
  const expected = PNG.sync.read(readFileSync(file));
  expect(Buffer.compare(Buffer.from(expected.data), Buffer.from(png.data))).toBe(0);
}

describe("M5Renderer", () => {
  it("starts black at native size", () => {
    const r = mk();
    expect(r.width()).toBe(135); expect(r.height()).toBe(240);
    expect(r.fb.getPixel(0, 0)).toBe(0x000000);
  });
  it("fill_rect paints and clips", () => {
    const r = mk();
    r.exec([["fill_rect", 10, 20, 30, 40, 0xff0000]]);
    expect(r.fb.getPixel(10, 20)).toBe(0xff0000);
    expect(r.fb.getPixel(39, 59)).toBe(0xff0000);
    expect(r.fb.getPixel(40, 60)).toBe(0x000000);
    expect(() => r.exec([["fill_rect", -50, -50, 1000, 1000, 0x00ff00]])).not.toThrow();
    expect(r.fb.getPixel(134, 239)).toBe(0x00ff00);
    expect(() => r.exec([["draw_string", "wide text past the edge", 120, 230]])).not.toThrow();
  });
  it("rotation 1 swaps dimensions and maps coordinates", () => {
    const r = mk();
    r.exec([["set_rotation", 1], ["draw_pixel", 0, 0, 0x0000ff]]);
    expect(r.width()).toBe(240); expect(r.height()).toBe(135);
    // rotation 1 (90 degrees clockwise): logical (0,0) is the native top-right pixel
    expect(r.fb.getPixel(134, 0)).toBe(0x0000ff);
  });
  it("draws text with the 6x8 font, white on black", () => {
    const r = mk();
    r.exec([["draw_string", "A", 0, 0]]);
    // 'A' column 0 is 0x7C: rows 2..6 set, rows 0,1 and 7 clear
    expect(r.fb.getPixel(0, 0)).toBe(0x000000);
    expect(r.fb.getPixel(0, 1)).toBe(0x000000);
    expect(r.fb.getPixel(0, 2)).toBe(0xffffff);
    expect(r.fb.getPixel(0, 6)).toBe(0xffffff);
    expect(r.fb.getPixel(0, 7)).toBe(0x000000);
    expect(r.fb.getPixel(5, 3)).toBe(0x000000); // spacing column
    expectGolden(r, "text-A");
  });
  it("print advances the cursor and wraps", () => {
    const r = mk();
    r.exec([["set_cursor", 0, 0], ["print", "xxxxxxxxxxxxxxxxxxxxxxx"]]); // 23 x
    expect(r.cursor).toEqual({ x: 6, y: 8 });
    r.exec([["println"]]);
    expect(r.cursor).toEqual({ x: 0, y: 16 });
    r.exec([["set_text_size", 2, 2], ["print", "A"]]);
    expect(r.cursor).toEqual({ x: 12, y: 16 });
    expect(r.fb.getPixel(0, 20)).toBe(0xffffff); // scaled glyph row 2 -> y 20,21
    expectGolden(r, "print-wrap-size2");
  });
  it("advances the cursor by code point and boxes unknown glyphs", () => {
    const r = mk();
    r.exec([["set_cursor", 0, 0], ["print", "é€\u{1f600}"]]); // 3 code points, 2 not in Font0
    expect(r.cursor).toEqual({ x: 18, y: 0 });
    r.exec([["draw_string", "€", 0, 20]]);
    expect(r.fb.getPixel(0, 20)).toBe(0xffffff); // box outline top-left
    expect(r.fb.getPixel(2, 23)).toBe(0x000000); // box interior
  });
  it("sleep blanks and wakeup restores", () => {
    const r = mk();
    r.exec([["fill_screen", 0x123456], ["sleep"]]);
    expect(r.sleeping).toBe(true);
    expect(r.fb.getPixel(5, 5)).toBe(0x123456); // framebuffer kept; presentation blanks
    r.exec([["wakeup"]]);
    expect(r.sleeping).toBe(false);
  });
  it("forwards tone and led as events", () => {
    const r = mk(); const seen: any[] = [];
    r.onEvent = (n, a) => seen.push([n, ...a]);
    r.exec([["tone", 440, 100, 64], ["led", "on"], ["stop_tone"]]);
    expect(seen).toEqual([["tone", 440, 100, 64], ["led", "on"], ["stop_tone"]]);
  });
  it("shapes golden", () => {
    const r = mk();
    r.exec([["fill_screen", 0x202020], ["draw_rect", 5, 5, 50, 30, 0xffff00], ["fill_circle", 67, 120, 20, 0x00ffff],
            ["draw_circle", 67, 120, 30, 0xff00ff], ["draw_line", 0, 239, 134, 0, 0xffffff],
            ["fill_round_rect", 20, 180, 95, 40, 8, 0x4080ff], ["draw_fast_hline", 0, 100, 135, 0xff0000],
            ["draw_fast_vline", 67, 0, 240, 0x00ff00], ["fill_triangle", 10, 230, 60, 200, 110, 230, 0xffa500]]);
    expectGolden(r, "shapes");
  });
  it("more shapes golden (ellipses, outlines)", () => {
    const r = mk();
    r.exec([["draw_ellipse", 67, 40, 50, 20, 0xff8000], ["fill_ellipse", 67, 100, 30, 15, 0x00ff80],
            ["draw_round_rect", 10, 130, 100, 40, 10, 0x80ffff], ["draw_triangle", 10, 230, 60, 190, 120, 230, 0xff0080]]);
    expectGolden(r, "shapes2");
  });
  it("rotation 1 golden", () => {
    const r = mk();
    r.exec([["set_rotation", 1], ["fill_screen", 0x101030], ["draw_rect", 0, 0, 240, 135, 0xffffff],
            ["fill_circle", 200, 90, 20, 0xff4040], ["draw_string", "rot 1", 10, 10],
            ["set_cursor", 10, 30], ["set_text_size", 2, 2], ["print", "wrap this long line of text past the edge"]]);
    expectGolden(r, "rotation-1");
  });
});
