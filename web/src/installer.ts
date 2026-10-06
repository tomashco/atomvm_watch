import { ESPLoader, Transport } from "esptool-js";
import type { BoardProfile } from "./board";
import type { LoadedApp } from "./loader";
import { parseManifest, checkChip } from "./flash";

/** One open serial session: transport connected, ROM synced. Always `close()` it. */
export interface Session {
  chip(): string;
  write(parts: { data: Uint8Array; address: number }[], onProgress: (pct: number) => void): Promise<void>;
  reset(): Promise<void>;
  close(): Promise<void>;
}
/** The port is chosen once; every operation opens (and closes) its own session on it. */
export interface Flasher {
  requestPort(): Promise<unknown>;
  open(port: unknown): Promise<Session>;
}
type Log = { out(l: string): void; err(l: string): void };

export const DOWNLOAD_MODE_HINT = "Hold the power button while plugging in USB to enter download mode";

export function esptoolFlasher(log: Log): Flasher {
  return {
    async requestPort() {
      if (!("serial" in navigator)) throw new Error("Web Serial is not available; use Chrome or Edge over HTTPS or localhost");
      return (navigator as Navigator & { serial: { requestPort(): Promise<unknown> } }).serial.requestPort();
    },
    async open(port) {
      const transport = new Transport(port as ConstructorParameters<typeof Transport>[0], true);
      const loader = new ESPLoader({
        transport, baudrate: 460800, enableTracing: false,
        terminal: { clean() {}, writeLine: (s) => log.out(s), write: (s) => log.out(s) },
      });
      let chip: string;
      try { chip = await loader.main(); }
      catch (e) { await transport.disconnect().catch(() => {}); throw e; }
      return {
        chip: () => chip,
        async write(parts, onProgress) {
          const total = parts.reduce((n, p) => n + p.data.length, 0);
          const done: number[] = parts.map(() => 0);
          await loader.writeFlash({
            fileArray: parts.map((p) => ({ data: p.data, address: p.address })),
            flashSize: "keep", flashMode: "keep", flashFreq: "keep", eraseAll: false, compress: true,
            // `written` is cumulative within one file, so track each file separately.
            reportProgress: (i, written, fileTotal) => {
              done[i] = Math.min(written, fileTotal);
              onProgress(Math.round((100 * done.reduce((a, b) => a + b, 0)) / total));
            },
          });
        },
        async reset() { await loader.after("hard_reset"); },
        async close() { await transport.disconnect(); },
      };
    },
  };
}

export function setupInstaller(
  profile: BoardProfile,
  els: { connect: HTMLButtonElement; runtime: HTMLButtonElement; app: HTMLButtonElement; chip: HTMLElement; progress: HTMLProgressElement; section?: HTMLElement },
  currentApp: () => LoadedApp | undefined,
  con: Log,
  flasher?: Flasher,
): { appChanged(): void } {
  if (!flasher) {
    if (!("serial" in navigator)) { if (els.section) els.section.hidden = true; return { appChanged() {} }; }
    flasher = esptoolFlasher(con);
  }
  const fl = flasher;
  let port: unknown;
  let connected = false;
  let working = false;
  let chipRejected = false;
  const sync = () => {
    els.connect.disabled = working;
    els.runtime.disabled = working || !connected;
    els.app.disabled = working || !connected || !currentApp();
  };
  sync();
  const progress = (pct: number) => { els.progress.hidden = false; els.progress.value = pct; };
  // Open a session, refuse a wrong chip, run fn, and always close the port.
  const inSession = async <T>(fn: (s: Session) => Promise<T>): Promise<T> => {
    const s = await fl.open(port);
    try {
      try { checkChip(profile.chip, s.chip()); } catch (e) { chipRejected = true; throw e; }
      return await fn(s);
    }
    finally { await s.close().catch((e) => con.err(`warning: closing the serial port failed: ${(e as Error).message}`)); }
  };
  const exclusive = async (fn: () => Promise<void>) => {
    if (working) return;
    working = true; sync();
    try { await fn(); } finally { working = false; els.progress.hidden = true; sync(); }
  };
  els.connect.addEventListener("click", () => exclusive(async () => {
    connected = false; chipRejected = false;
    try { port = await fl.requestPort(); }
    catch (e) { con.err((e as Error).message); return; }
    let chip = "";
    try {
      await inSession(async (s) => { chip = s.chip(); });
      els.chip.textContent = chip; connected = true;
    } catch (e) {
      const m = (e as Error).message;
      // A wrong chip is not a download-mode problem.
      if (!chipRejected) con.err(`${m}. ${DOWNLOAD_MODE_HINT}`);
      else con.err(m);
    }
  }));
  const install = (label: string, make: () => Promise<{ data: Uint8Array; address: number }[]>) => exclusive(async () => {
    try {
      con.out(`${label}...`);
      const parts = await make();
      await inSession(async (s) => {
        await s.write(parts, progress);
        try { await s.reset(); } catch (e) { con.err(`warning: could not reset the device after ${label}: ${(e as Error).message}; press the reset button on the device`); }
      });
      con.out(`${label} done`);
    } catch (e) { con.err(`${label} failed: ${(e as Error).message}`); }
  });
  els.runtime.addEventListener("click", () => install("Install runtime", async () => {
    const res = await fetch(profile.firmwareManifest);
    if (!res.ok) throw new Error(`firmware manifest ${profile.firmwareManifest} not found (${res.status}); no runtime is published at this address yet`);
    const manifest = parseManifest(await res.json());
    if (manifest.chip.toUpperCase() !== profile.chip.toUpperCase()) throw new Error(`manifest is for ${manifest.chip}, this board needs ${profile.chip}`);
    if (manifest.appOffset !== profile.appOffset) throw new Error(`manifest appOffset 0x${manifest.appOffset.toString(16)} does not match the board profile's 0x${profile.appOffset.toString(16)}`);
    const base = profile.firmwareManifest.slice(0, profile.firmwareManifest.lastIndexOf("/") + 1);
    return Promise.all(manifest.parts.map(async (p) => {
      const r = await fetch(base + p.path);
      if (!r.ok) throw new Error(`${p.path} not found (${r.status})`);
      return { data: new Uint8Array(await r.arrayBuffer()), address: p.offset };
    }));
  }));
  els.app.addEventListener("click", () => install("Install app", async () => {
    const app = currentApp(); if (!app) throw new Error("load an app first");
    return [{ data: app.bytes, address: profile.appOffset }];
  }));
  return { appChanged: sync };
}
