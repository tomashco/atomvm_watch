// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";
import { setupInstaller, type Flasher, type Session } from "../src/installer";
import { parseBoardProfile } from "../src/board";
import { readFileSync } from "node:fs";
import { join } from "node:path";
const p = parseBoardProfile(JSON.parse(readFileSync(join(import.meta.dirname, "../../boards/m5stickc_plus2/board.json"), "utf8")));
function els() {
  const mk = (tag: string) => document.createElement(tag);
  return { connect: mk("button") as HTMLButtonElement, runtime: mk("button") as HTMLButtonElement, app: mk("button") as HTMLButtonElement, chip: mk("span"), progress: mk("progress") as HTMLProgressElement };
}
const tick = () => new Promise((r) => setTimeout(r, 0));
const mkCon = () => ({ out: vi.fn(), err: vi.fn(), clear: vi.fn() });
afterEach(() => vi.unstubAllGlobals());
function fake(chip: string, opts: { openFails?: boolean; resetFails?: boolean } = {}) {
  const log: string[] = []; const writes: { data: Uint8Array; address: number }[] = [];
  const flasher: Flasher = {
    requestPort: async () => { log.push("port"); return "P"; },
    open: async () => {
      log.push("open");
      if (opts.openFails) throw new Error("Failed to connect");
      const s: Session = {
        chip: () => chip,
        write: async (parts) => { log.push("write"); writes.push(...parts); },
        reset: async () => { log.push("reset"); if (opts.resetFails) throw new Error("boom"); },
        close: async () => { log.push("close"); },
      };
      return s;
    },
  };
  return { flasher, log, writes };
}
const manifestFetch = (manifest: unknown) => vi.stubGlobal("fetch", vi.fn(async (u: string) => u.endsWith(".json")
  ? { ok: true, json: async () => manifest }
  : { ok: true, arrayBuffer: async () => new Uint8Array([1, 2, 3]).buffer }));
const goodManifest = { version: "1", chip: "ESP32", atomvm: "v", parts: [{ path: "a.img", offset: 4096 }], appOffset: 0x250000 };
const settle = async () => { for (let i = 0; i < 6; i++) await tick(); };

describe("setupInstaller", () => {
  it("connect probes the chip then closes the port", async () => {
    const con = mkCon(); const { flasher, log } = fake("ESP32-PICO-V3-02");
    const e = els(); setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await settle();
    expect(log).toEqual(["port", "open", "close"]);
    expect(e.runtime.disabled).toBe(false); expect(e.app.disabled).toBe(true);
    expect(e.chip.textContent).toBe("ESP32-PICO-V3-02");
  });
  it("runtime then app install each do open, write, reset, close", async () => {
    const con = mkCon(); manifestFetch(goodManifest);
    const { flasher, log, writes } = fake("ESP32-D0WD-V3");
    const e = els(); const app = { name: "clock.avm", bytes: new Uint8Array([9, 9]) };
    setupInstaller(p, e, () => app, con, flasher);
    e.connect.click(); await settle(); log.length = 0;
    e.runtime.click(); await settle();
    e.app.click(); await settle();
    expect(log).toEqual(["open", "write", "reset", "close", "open", "write", "reset", "close"]);
    expect(writes).toEqual([{ data: new Uint8Array([1, 2, 3]), address: 0x1000 }, { data: app.bytes, address: 0x250000 }]);
  });
  it("wrong chip refuses, closes the port and keeps buttons disabled", async () => {
    const con = mkCon(); const { flasher, log } = fake("ESP32-S3");
    const e = els(); setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await settle();
    expect(log).toEqual(["port", "open", "close"]);
    expect(e.app.disabled).toBe(true); expect(e.runtime.disabled).toBe(true);
    expect(con.err).toHaveBeenCalledWith(expect.stringMatching(/ESP32-S3/));
    expect(con.err).not.toHaveBeenCalledWith(expect.stringMatching(/Hold the power button/));
  });
  it("wrong chip at install time closes the port without writing", async () => {
    const con = mkCon(); const { flasher, log } = fake("ESP32");
    const e = els(); setupInstaller(p, e, () => ({ name: "a", bytes: new Uint8Array([1]) }), con, flasher);
    e.connect.click(); await settle(); log.length = 0;
    const swap = vi.spyOn(flasher, "open").mockImplementation(async () => { log.push("open"); return { chip: () => "ESP32-C3", write: async () => { log.push("write"); }, reset: async () => {}, close: async () => { log.push("close"); } }; });
    e.app.click(); await settle();
    swap.mockRestore();
    expect(log).toEqual(["open", "close"]);
  });
  it("failed connect shows the download-mode hint and can be retried", async () => {
    const con = mkCon(); const { flasher } = fake("ESP32", { openFails: true });
    const e = els(); setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await settle();
    expect(con.err).toHaveBeenCalledWith(expect.stringMatching(/Hold the power button while plugging in USB to enter download mode/));
    expect(e.connect.disabled).toBe(false);
  });
  it("a failed reset after a good write is a warning, not a failure", async () => {
    const con = mkCon(); const { flasher, log } = fake("ESP32", { resetFails: true });
    const e = els(); setupInstaller(p, e, () => ({ name: "a", bytes: new Uint8Array([1]) }), con, flasher);
    e.connect.click(); await settle(); log.length = 0;
    e.app.click(); await settle();
    expect(log).toEqual(["open", "write", "reset", "close"]);
    expect(con.out).toHaveBeenCalledWith("Install app done");
    expect(con.err).not.toHaveBeenCalledWith(expect.stringMatching(/Install app failed/));
    expect(con.err).toHaveBeenCalledWith(expect.stringMatching(/warning: could not reset/));
  });
  it("disables everything while an operation runs", async () => {
    const con = mkCon(); let release!: () => void;
    const { flasher } = fake("ESP32");
    const open = flasher.open;
    const e = els(); setupInstaller(p, e, () => ({ name: "a", bytes: new Uint8Array([1]) }), con, flasher);
    e.connect.click(); await settle();
    flasher.open = async (pt) => { const s = await open(pt); const w = s.write; s.write = async (...a) => { await new Promise<void>((r) => { release = r; }); return w(...a); }; return s; };
    e.app.click(); await settle();
    expect(e.connect.disabled).toBe(true); expect(e.runtime.disabled).toBe(true); expect(e.app.disabled).toBe(true);
    release(); await settle();
    expect(e.connect.disabled).toBe(false); expect(e.app.disabled).toBe(false);
  });
  it("appChanged enables Install app once an app is loaded", async () => {
    const con = mkCon(); const { flasher } = fake("ESP32");
    let app: { name: string; bytes: Uint8Array } | undefined;
    const e = els(); const inst = setupInstaller(p, e, () => app, con, flasher);
    e.connect.click(); await settle();
    expect(e.app.disabled).toBe(true);
    app = { name: "a", bytes: new Uint8Array([1]) }; inst.appChanged();
    expect(e.app.disabled).toBe(false);
  });
  it("missing manifest logs a clear error and writes nothing", async () => {
    const con = mkCon(); vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 404 })));
    const { flasher, log } = fake("ESP32");
    const e = els(); setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await settle(); log.length = 0;
    e.runtime.click(); await settle();
    expect(con.err).toHaveBeenCalledWith(expect.stringMatching(/Install runtime failed.*404/));
    expect(log).toEqual([]);
  });
  it("refuses a manifest whose appOffset differs from the profile", async () => {
    const con = mkCon(); manifestFetch({ ...goodManifest, appOffset: 0x300000 });
    const { flasher, log } = fake("ESP32");
    const e = els(); setupInstaller(p, e, () => undefined, con, flasher);
    e.connect.click(); await settle(); log.length = 0;
    e.runtime.click(); await settle();
    expect(con.err).toHaveBeenCalledWith(expect.stringMatching(/appOffset 0x300000/));
    expect(log).toEqual([]);
  });
  it("hides the section when Web Serial is missing", () => {
    const e = { ...els(), section: document.createElement("details") };
    setupInstaller(p, e, () => undefined, mkCon());
    expect(e.section.hidden).toBe(true);
  });
});
