import { ESPLoader, Transport } from "esptool-js";
import type { BoardProfile } from "./board";
import type { LoadedApp } from "./loader";
import { parseManifest, checkChip } from "./flash";

export interface Flasher {
  connect(): Promise<string>;
  write(parts: { data: Uint8Array; address: number }[], onProgress: (pct: number) => void): Promise<void>;
  reset(): Promise<void>;
}
type Log = { out(l: string): void; err(l: string): void };

export const DOWNLOAD_MODE_HINT = "Hold the power button while plugging in USB to enter download mode";

export function esptoolFlasher(log: Log): Flasher {
  let loader: ESPLoader | undefined;
  return {
    async connect() {
      if (!("serial" in navigator)) throw new Error("Web Serial is not available; use Chrome or Edge over HTTPS or localhost");
      const port = await (navigator as Navigator & { serial: { requestPort(): Promise<ConstructorParameters<typeof Transport>[0]> } }).serial.requestPort();
      const transport = new Transport(port, true);
      loader = new ESPLoader({
        transport, baudrate: 460800, enableTracing: false,
        terminal: { clean() {}, writeLine: (s) => log.out(s), write: (s) => log.out(s) },
      });
      return await loader.main();
    },
    async write(parts, onProgress) {
      if (!loader) throw new Error("not connected");
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
    async reset() { await loader?.after("hard_reset"); },
  };
}

export function setupInstaller(
  profile: BoardProfile,
  els: { connect: HTMLElement; runtime: HTMLButtonElement; app: HTMLButtonElement; chip: HTMLElement; progress: HTMLProgressElement; section?: HTMLElement },
  currentApp: () => LoadedApp | undefined,
  con: Log,
  flasher?: Flasher,
): void {
  if (!flasher) {
    if (!("serial" in navigator)) { if (els.section) els.section.hidden = true; return; }
    flasher = esptoolFlasher(con);
  }
  const fl = flasher;
  const progress = (pct: number) => { els.progress.hidden = false; els.progress.value = pct; };
  const busy = async (label: string, fn: () => Promise<void>) => {
    els.runtime.disabled = els.app.disabled = true;
    try { con.out(`${label}...`); await fn(); await fl.reset(); con.out(`${label} done`); }
    catch (e) { con.err(`${label} failed: ${(e as Error).message}`); }
    finally { els.runtime.disabled = false; els.app.disabled = !currentApp(); els.progress.hidden = true; }
  };
  els.connect.addEventListener("click", async () => {
    els.runtime.disabled = els.app.disabled = true;
    let chip: string;
    try { chip = await fl.connect(); }
    catch (e) { con.err(`${(e as Error).message}. ${DOWNLOAD_MODE_HINT}`); return; }
    els.chip.textContent = chip;
    try { checkChip(profile.chip, chip); }
    catch (e) { con.err((e as Error).message); return; }
    els.runtime.disabled = false; els.app.disabled = !currentApp();
  });
  els.runtime.addEventListener("click", () => busy("Install runtime", async () => {
    const res = await fetch(profile.firmwareManifest);
    if (!res.ok) throw new Error(`firmware manifest ${profile.firmwareManifest} not found (${res.status}); no runtime is published at this address yet`);
    const manifest = parseManifest(await res.json());
    if (manifest.chip.toUpperCase() !== profile.chip.toUpperCase()) throw new Error(`manifest is for ${manifest.chip}, this board needs ${profile.chip}`);
    const base = profile.firmwareManifest.slice(0, profile.firmwareManifest.lastIndexOf("/") + 1);
    const parts = await Promise.all(manifest.parts.map(async (p) => {
      const r = await fetch(base + p.path);
      if (!r.ok) throw new Error(`${p.path} not found (${r.status})`);
      return { data: new Uint8Array(await r.arrayBuffer()), address: p.offset };
    }));
    await fl.write(parts, progress);
  }));
  els.app.addEventListener("click", () => busy("Install app", async () => {
    const app = currentApp(); if (!app) throw new Error("load an app first");
    await fl.write([{ data: app.bytes, address: profile.appOffset }], progress);
  }));
}
