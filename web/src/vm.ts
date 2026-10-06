export interface VmFactory { (opts: Record<string, unknown>): Promise<{ cast(name: string, msg: string): void }> }
export interface VmHandle { cast(name: string, msg: string): void; exited: Promise<number> }

/** The AtomVM web build's module factory, loaded at runtime from public/atomvm/ (not bundled). */
export async function defaultFactory(): Promise<VmFactory> {
  const base = import.meta.env.BASE_URL;
  const mod = await import(/* @vite-ignore */ new URL(`${base}atomvm/AtomVM.mjs`, location.href).href);
  return mod.default as VmFactory;
}

/**
 * Packs for every VM start, in this order (X1): our m5_emu shim first, then the AtomVM stdlib,
 * then the app. AtomVM resolves a module from the first pack that has it, so m5_emu's `gpio`
 * shadows the one in atomvmlib.
 * URLs are absolute: AtomVM fetches them from a pthread worker whose script is
 * atomvm/AtomVM.mjs, so a relative "./m5_emu.avm" (base "./" after build) would resolve to
 * atomvm/m5_emu.avm, and a static host's fallback page would be parsed as a pack.
 */
export function packUrls(base: string, appUrl: string, pageUrl: string): string[] {
  const abs = (p: string) => new URL(`${base}${p}`, pageUrl).href;
  return [abs("m5_emu.avm"), abs("atomvm/atomvmlib.avm"), appUrl];
}

// AtomVM stderr lines that mean the app was built for a different AtomVM / OTP than this VM.
const VERSION_SYMPTOMS = [
  /Cannot load startup module/,
  /main module not loaded/,
  /missing opcode/,
  /Unknown native code chunk version/,
];

/** A console hint naming the expected AtomVM version when stderr looks like a version mismatch. */
export function versionHint(line: string, expected: string): string | undefined {
  if (!VERSION_SYMPTOMS.some((re) => re.test(line))) return undefined;
  return `This emulator runs AtomVM ${expected}. Rebuild the app against AtomVM ${expected} ` +
    `(and check it has a start module) if it was packed for another version.`;
}

// The web build is linked with noExitRuntime = true (the module only overrides it when the option
// is truthy), so Module.onExit never fires when main returns. AtomVM's own output marks the end
// instead: globalcontext_run prints "Return value: <term>" on stdout (ok or 0 means success), and
// main.c's load errors on stderr make main return EXIT_FAILURE before anything runs.
const RETURN_VALUE = /^Return value: (.*)$/;
const LOAD_FAILURE = [
  /^Failed opening /,
  /^Cannot load startup module/,
  /^main module not loaded/,
  / is not an AVM or BEAM file\.$/,
  /^No \.avm or \.beam module specified/,
];

export async function startVm(o: {
  factory: VmFactory; avmUrls: string[]; onStdout(l: string): void; onStderr(l: string): void;
}): Promise<VmHandle> {
  let resolveExit!: (code: number) => void;
  const exited = new Promise<number>((r) => (resolveExit = r));
  const module = await o.factory({
    arguments: o.avmUrls,
    print: (line: string) => {
      o.onStdout(line);
      const m = RETURN_VALUE.exec(line);
      if (m) resolveExit(m[1] === "ok" || m[1] === "0" ? 0 : 1);
    },
    printErr: (line: string) => {
      o.onStderr(line);
      if (LOAD_FAILURE.some((re) => re.test(line))) resolveExit(1);
    },
    onExit: (code: number) => resolveExit(code),
    onAbort: (what: unknown) => { o.onStderr(`AtomVM aborted: ${String(what)}`); resolveExit(1); },
    noExitRuntime: false,
  });
  // After main returns AtomVM has destroyed its global context; a cast then dereferences freed
  // memory and can hang the browser's main thread, so casts stop at the first exit signal.
  let alive = true;
  void exited.then(() => { alive = false; });
  return { cast: (n, m) => { if (alive) module.cast(n, m); }, exited };
}
