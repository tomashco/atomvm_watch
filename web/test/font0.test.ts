import { it, expect } from "vitest";
import { FONT0, GLYPH_W } from "../src/font0";
it("has 256 glyphs of 5 columns", () => expect(FONT0.length).toBe(256 * GLYPH_W));
it("glyph 'A' matches LovyanGFX 1.2.0 glcdfont", () => {
  expect([...FONT0.slice(0x41 * 5, 0x41 * 5 + 5)]).toEqual([0x7c, 0x12, 0x11, 0x12, 0x7c]);
});
