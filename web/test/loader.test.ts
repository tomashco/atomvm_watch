import "fake-indexeddb/auto";
import { describe, it, expect } from "vitest";
import { appFromFile, appUrl, saveLastApp, loadLastApp } from "../src/loader";
describe("loader", () => {
  it("reads a dropped file", async () => {
    const f = new File([new Uint8Array([1, 2, 3])], "clock.avm");
    const app = await appFromFile(f);
    expect(app.name).toBe("clock.avm"); expect([...app.bytes]).toEqual([1, 2, 3]);
  });
  it("rejects non-avm files", async () => {
    await expect(appFromFile(new File([""], "x.beam"))).rejects.toThrow(/\.avm/);
  });
  it("saving twice overwrites the IndexedDB entry: the last saved app is loaded", async () => {
    await saveLastApp({ name: "a.avm", bytes: new Uint8Array([1]) });
    await saveLastApp({ name: "b.avm", bytes: new Uint8Array([2]) });
    const last = await loadLastApp();
    expect(last?.name).toBe("b.avm"); expect([...last!.bytes]).toEqual([2]);
  });
  it("app URL is a blob URL ending in .avm, so AtomVM's suffix check passes", () => {
    const u = appUrl({ name: "clock.avm", bytes: new Uint8Array([1]) });
    expect(u.startsWith("blob:")).toBe(true);
    expect(u.endsWith(".avm")).toBe(true);
  });
});
