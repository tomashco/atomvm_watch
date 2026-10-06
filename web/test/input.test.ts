// @vitest-environment jsdom
import { describe, it, expect } from "vitest";
import { bindInputs } from "../src/input";
import { parseBoardProfile } from "../src/board";
import { readFileSync } from "node:fs";
import { join } from "node:path";
// A path, not new URL(..., import.meta.url): jsdom replaces the global URL and node:fs rejects it.
const p = parseBoardProfile(JSON.parse(readFileSync(join(import.meta.dirname, "../../boards/m5stickc_plus2/board.json"), "utf8")));
describe("bindInputs", () => {
  it("renders a button per profile entry and casts down/up", () => {
    const root = document.createElement("div"); const sent: string[] = [];
    const unbind = bindInputs(p, root, (m) => sent.push(m));
    const a = root.querySelector<HTMLButtonElement>('[data-btn="a"]')!;
    expect(root.querySelectorAll("[data-btn]").length).toBe(3);
    a.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true }));
    a.dispatchEvent(new MouseEvent("pointerup", { bubbles: true }));
    unbind();
    expect(sent).toEqual(["a:down", "a:up"]);
  });
  it("maps keyboard shortcuts and ignores repeats", () => {
    const root = document.createElement("div"); const sent: string[] = [];
    document.body.appendChild(root);
    const unbind = bindInputs(p, root, (m) => sent.push(m));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "p" }));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "p", repeat: true }));
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "p" }));
    unbind();
    expect(sent).toEqual(["pwr:down", "pwr:up"]);
  });
  it("battery slider casts batt:N", () => {
    const root = document.createElement("div"); const sent: string[] = [];
    const unbind = bindInputs(p, root, (m) => sent.push(m));
    const s = root.querySelector<HTMLInputElement>('input[type="range"]')!;
    s.value = "37"; s.dispatchEvent(new Event("input", { bubbles: true }));
    unbind();
    expect(sent).toEqual(["batt:37"]);
  });
});
