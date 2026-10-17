import type { BoardProfile } from "./board";
import { buttonMessage, batteryMessage } from "./protocol";

/** Renders the profile's buttons and battery slider into `root` and maps keyboard shortcuts. */
export function bindInputs(profile: BoardProfile, root: HTMLElement, cast: (msg: string) => void): () => void {
  const held = new Set<string>();
  const down = (id: string) => { if (held.has(id)) return; held.add(id); cast(buttonMessage(id, true)); };
  const up = (id: string) => { if (!held.has(id)) return; held.delete(id); cast(buttonMessage(id, false)); };

  const bar = document.createElement("div"); bar.className = "buttons";
  for (const b of profile.buttons) {
    const el = document.createElement("button");
    el.type = "button"; el.dataset.btn = b.id; el.textContent = `${b.label} (${b.key})`;
    el.addEventListener("pointerdown", () => down(b.id));
    el.addEventListener("pointerup", () => up(b.id));
    el.addEventListener("pointerleave", () => up(b.id));
    bar.appendChild(el);
  }
  root.appendChild(bar);

  let battery: HTMLElement | undefined;
  if (profile.peripherals.battery) {
    const label = document.createElement("label"); label.className = "battery"; label.textContent = "Battery ";
    const s = document.createElement("input");
    s.type = "range"; s.min = "0"; s.max = "100"; s.value = "100"; s.title = "Battery";
    const pct = document.createElement("span"); pct.textContent = "100%";
    s.addEventListener("input", () => { pct.textContent = `${s.value}%`; cast(batteryMessage(Number(s.value))); });
    label.append(s, pct);
    root.appendChild(label);
    battery = label;
  }

  const byKey = new Map(profile.buttons.map((b) => [b.key.toLowerCase(), b.id]));
  const typing = (e: KeyboardEvent) => e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement;
  const kd = (e: KeyboardEvent) => {
    if (e.repeat || typing(e)) return;
    const id = byKey.get(e.key.toLowerCase()); if (id) { e.preventDefault(); down(id); }
  };
  const ku = (e: KeyboardEvent) => { const id = byKey.get(e.key.toLowerCase()); if (id) up(id); };
  window.addEventListener("keydown", kd); window.addEventListener("keyup", ku);
  return () => {
    window.removeEventListener("keydown", kd); window.removeEventListener("keyup", ku);
    bar.remove(); battery?.remove();
  };
}
