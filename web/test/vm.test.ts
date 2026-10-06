import { describe, it, expect } from "vitest";
import { startVm, packUrls, versionHint } from "../src/vm";

function fakeFactory(script: (m: any) => void) {
  return async (opts: any) => {
    const m = { cast: (_n: string, _s: string) => {}, opts };
    queueMicrotask(() => script({ ...m, print: opts.print, printErr: opts.printErr, onExit: opts.onExit }));
    return m;
  };
}
describe("startVm", () => {
  it("passes library then app and relays stdout", async () => {
    const out: string[] = [];
    const vm = await startVm({
      factory: fakeFactory((m) => { m.print("hello"); m.onExit(0); }),
      avmUrls: ["/m5_emu.avm", "blob:app"], onStdout: (l) => out.push(l), onStderr: () => {},
    });
    expect(await vm.exited).toBe(0);
    expect(out).toEqual(["hello"]);
  });
  it("exit with error surfaces stderr", async () => {
    const err: string[] = [];
    const vm = await startVm({
      factory: fakeFactory((m) => { m.printErr("Cannot load startup module: boom"); m.onExit(1); }),
      avmUrls: ["/m5_emu.avm", "blob:app"], onStdout: () => {}, onStderr: (l) => err.push(l),
    });
    expect(await vm.exited).toBe(1);
    expect(err[0]).toMatch(/startup module/);
  });
  // The web build keeps the runtime alive after main returns, so onExit never fires there; the
  // exit is read from AtomVM's own last lines instead.
  it("treats AtomVM's 'Return value:' line as the exit (ok -> 0, else 1)", async () => {
    const out: string[] = [];
    const ok = await startVm({ factory: fakeFactory((m) => m.print("Return value: ok")),
      avmUrls: [], onStdout: (l) => out.push(l), onStderr() {} });
    expect(await ok.exited).toBe(0);
    expect(out).toEqual(["Return value: ok"]);
    const bad = await startVm({ factory: fakeFactory((m) => m.print("Return value: error")),
      avmUrls: [], onStdout() {}, onStderr() {} });
    expect(await bad.exited).toBe(1);
  });
  it("treats a pack load failure on stderr as exit 1", async () => {
    const vm = await startVm({ factory: fakeFactory((m) => m.printErr("Failed opening blob:x#/a.avm.")),
      avmUrls: [], onStdout() {}, onStderr() {} });
    expect(await vm.exited).toBe(1);
  });
  it("drops casts after the VM exited (AtomVM's global context is gone)", async () => {
    const casts: string[] = [];
    const vm = await startVm({
      factory: async (o: any) => { setTimeout(() => o.print("Return value: ok"), 0); return { cast: (_n: string, m: string) => casts.push(m) }; },
      avmUrls: [], onStdout() {}, onStderr() {},
    });
    vm.cast("p", "before");
    await vm.exited;
    vm.cast("p", "after");
    expect(casts).toEqual(["before"]);
  });
  it("sends the arguments in order", async () => {
    let seen: string[] = [];
    await startVm({ factory: async (o: any) => { seen = o.arguments; return { cast() {} }; },
      avmUrls: ["/m5_emu.avm", "blob:app"], onStdout() {}, onStderr() {} });
    expect(seen).toEqual(["/m5_emu.avm", "blob:app"]);
  });
});
describe("packUrls", () => {
  it("loads m5_emu, then atomvmlib, then the app (X1: first pack wins)", () => {
    expect(packUrls("/", "blob:x#/clock.avm", "http://h/")).toEqual(
      ["http://h/m5_emu.avm", "http://h/atomvm/atomvmlib.avm", "blob:x#/clock.avm"]);
  });
  // The VM fetches from a pthread worker whose script is atomvm/AtomVM.mjs, so a relative
  // "./m5_emu.avm" would resolve to atomvm/m5_emu.avm. Packs are resolved against the page.
  it("resolves a relative base against the page, not the worker", () => {
    expect(packUrls("./", "blob:x#/a.avm", "https://u.github.io/atomvm_watch/?board=x")).toEqual([
      "https://u.github.io/atomvm_watch/m5_emu.avm",
      "https://u.github.io/atomvm_watch/atomvm/atomvmlib.avm",
      "blob:x#/a.avm",
    ]);
  });
});
describe("versionHint", () => {
  it("names the expected AtomVM version on a missing start module", () => {
    expect(versionHint("Cannot load startup module: clock", "v0.7.0-beta.0")).toMatch(/v0\.7\.0-beta\.0/);
    expect(versionHint("main module not loaded", "v0.7.0-beta.0")).toMatch(/v0\.7\.0-beta\.0/);
  });
  it("names the expected AtomVM version on an opcode or version mismatch", () => {
    expect(versionHint("missing opcode: 182", "v0.7.0-beta.0")).toMatch(/v0\.7\.0-beta\.0/);
    expect(versionHint("Unknown native code chunk version (3)", "v0.7.0-beta.0")).toMatch(/v0\.7\.0-beta\.0/);
  });
  it("stays quiet on other stderr", () => {
    expect(versionHint("badarg in foo", "v0.7.0-beta.0")).toBeUndefined();
  });
});
