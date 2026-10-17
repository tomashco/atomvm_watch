export interface FirmwareManifest { version: string; chip: string; atomvm: string; parts: { path: string; offset: number }[]; appOffset: number }

export function parseManifest(json: unknown): FirmwareManifest {
  const m = (json ?? {}) as Partial<FirmwareManifest>;
  // parts first: it is the field most likely to be absent in a hand-edited manifest.
  for (const k of ["parts", "version", "chip", "atomvm", "appOffset"] as const) if (m[k] === undefined) throw new Error(`manifest missing ${k}`);
  if (!Array.isArray(m.parts) || m.parts.length === 0) throw new Error("manifest parts must be a non-empty array");
  return m as FirmwareManifest;
}

export function checkChip(expected: string, reported: string): void {
  // esptool reports e.g. "ESP32-D0WD-V3 (revision v3.1)", "ESP32-PICO-V3-02", "ESP32-S3", "ESP32-C3".
  const family = reported.split(/[\s(]/)[0];
  const bad = /^ESP32-(S|C|H|P)\d/i.test(family);
  if (bad || !family.toUpperCase().startsWith(expected.toUpperCase())) throw new Error(`connected chip is ${reported}, this board needs ${expected}`);
}
