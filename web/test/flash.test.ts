import { describe, it, expect } from "vitest";
import { parseManifest, checkChip } from "../src/flash";
describe("flash helpers", () => {
  it("parses a manifest", () => {
    const m = parseManifest({ version: "0.1.0", chip: "ESP32", atomvm: "v0.7.0-beta.0", parts: [{ path: "AtomVM-m5stickc_plus2-0.1.0.img", offset: 4096 }], appOffset: 2424832 });
    expect(m.parts[0].offset).toBe(0x1000); expect(m.appOffset).toBe(0x250000);
  });
  it("rejects a manifest without parts", () => { expect(() => parseManifest({ version: "1", chip: "ESP32" })).toThrow(/parts/); });
  it("wrong chip refuses", () => {
    expect(() => checkChip("ESP32", "ESP32-S3")).toThrow(/ESP32-S3/);
    expect(() => checkChip("ESP32", "ESP32-C3")).toThrow();
    expect(() => checkChip("ESP32", "ESP32-D0WD-V3 (revision v3.1)")).not.toThrow();
    expect(() => checkChip("ESP32", "ESP32-PICO-V3-02")).not.toThrow();
  });
});
