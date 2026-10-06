// @vitest-environment jsdom
import { describe, it, expect, vi } from "vitest";
import { setupInstaller, type Flasher } from "../src/installer";
import { parseBoardProfile } from "../src/board";
import { readFileSync } from "node:fs";
import { join } from "node:path";
const p = parseBoardProfile(JSON.parse(readFileSync(join(import.meta.dirname, "../../boards/m5stickc_plus2/board.json"), "utf8")));
function els() {
  const mk = (tag: string) => document.createElement(tag);
  return { connect: mk("button"), runtime: mk("button") as HTMLButtonElement, app: mk("button") as HTMLButtonElement, chip: mk("span"), progress: mk("progress") as HTMLProgressElement };
}
const tick = () => new Promise((r) => setTimeout(r, 0));
const mkCon = () => ({ out: vi.fn(), err: vi.fn(), clear: vi.fn() });
describe("setupInstaller", () => {
  it("writes the current app at the profile offset", async () => {
    const con = mkCon();
    const writes: any[] = [];
    const flasher: Flasher = { connect: async () => "ESP32-PICO-V3-02", write: async (parts) => { writes.push(...parts); }, reset: async () => {} };
    const e = els(); const app = { name: "clock.avm", bytes: new Uint8Array([9, 9]) };
    setupInstaller(p, e, () => app, con, flasher);
    e.connect.click(); await tick();
    expect(e.app.disabled).toBe(false);
    e.app.click(); await tick();
    expect(writes).toEqual([{ data: app.bytes, address: 0x250000 }]);
  });
  it("wrong chip refuses and keeps buttons disabled", async () => {
    const con = mkCon();
    const flasher: Flasher = { connect: async () => "ESP32-S3", write: vi.fn(async () => {}), reset: async () => {} };
    const e = els();
    setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await tick();
    expect(e.app.disabled).toBe(true); expect(e.runtime.disabled).toBe(true);
    expect(con.err).toHaveBeenCalledWith(expect.stringMatching(/ESP32-S3/));
    expect(flasher.write).not.toHaveBeenCalled();
  });
  it("failed connect shows the download-mode hint", async () => {
    const con = mkCon();
    const flasher: Flasher = { connect: async () => { throw new Error("Failed to connect"); }, write: async () => {}, reset: async () => {} };
    const e = els();
    setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await tick();
    expect(con.err).toHaveBeenCalledWith(expect.stringMatching(/Hold the power button while plugging in USB to enter download mode/));
  });
  it("install runtime writes manifest parts at their offsets", async () => {
    const con = mkCon();
    const manifest = { version: "1", chip: "ESP32", atomvm: "v", parts: [{ path: "a.img", offset: 4096 }], appOffset: 0x250000 };
    vi.stubGlobal("fetch", vi.fn(async (u: string) => u.endsWith(".json")
      ? { ok: true, json: async () => manifest }
      : { ok: true, arrayBuffer: async () => new Uint8Array([1, 2, 3]).buffer }));
    const writes: any[] = [];
    const flasher: Flasher = { connect: async () => "ESP32-D0WD-V3", write: async (parts) => { writes.push(...parts); }, reset: async () => {} };
    const e = els();
    setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await tick();
    e.runtime.click(); await tick(); await tick();
    vi.unstubAllGlobals();
    expect(writes).toEqual([{ data: new Uint8Array([1, 2, 3]), address: 0x1000 }]);
  });
  it("missing manifest logs a clear error", async () => {
    const con = mkCon();
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 404 })));
    const flasher: Flasher = { connect: async () => "ESP32", write: vi.fn(async () => {}), reset: async () => {} };
    const e = els();
    setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await tick();
    e.runtime.click(); await tick(); await tick();
    vi.unstubAllGlobals();
    expect(con.err).toHaveBeenCalledWith(expect.stringMatching(/Install runtime failed.*404/));
    expect(flasher.write).not.toHaveBeenCalled();
  });
  it("hides the section when Web Serial is missing", () => {
    const e = { ...els(), section: document.createElement("details") };
    setupInstaller(p, e, () => undefined, mkCon());
    expect(e.section.hidden).toBe(true);
  });
});
