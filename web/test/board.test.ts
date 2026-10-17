import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { parseBoardProfile } from "../src/board";
const raw = JSON.parse(readFileSync(new URL("../../boards/m5stickc_plus2/board.json", import.meta.url), "utf8"));
describe("parseBoardProfile", () => {
  it("accepts the m5stickc_plus2 profile", () => {
    const p = parseBoardProfile(raw);
    expect(p.boardAtom).toBe("stick_cplus2");
    expect(p.screen).toEqual({ width: 135, height: 240, scale: 1.5, x: 20, y: 40 });
    expect(p.appOffset).toBe(0x250000);
    expect(p.buttons.map(b => b.id)).toEqual(["a", "b", "pwr"]);
    expect(p.firmwareManifest).toBe("firmware/manifest-m5stickc_plus2.json");
  });
  it("rejects a profile missing the screen", () => {
    const { screen, ...rest } = raw;
    expect(() => parseBoardProfile(rest)).toThrow(/screen/);
  });
  it("rejects an unknown button id", () => {
    const bad = { ...raw, buttons: [{ id: "x", label: "X", key: "x", x: 0, y: 0 }] };
    expect(() => parseBoardProfile(bad)).toThrow(/buttons/);
  });
});
