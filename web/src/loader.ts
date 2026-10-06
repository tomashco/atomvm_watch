import { get, set } from "idb-keyval";
export interface LoadedApp { name: string; bytes: Uint8Array }
const KEY = "atomvm_watch.lastApp";

export async function appFromFile(f: File): Promise<LoadedApp> {
  if (!f.name.endsWith(".avm")) throw new Error(`expected a .avm file, got ${f.name}`);
  return { name: f.name, bytes: new Uint8Array(await f.arrayBuffer()) };
}

export async function appFromUrl(url: string): Promise<LoadedApp> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch ${url}: ${res.status}`);
  const name = new URL(url, location.href).pathname.split("/").pop() || "app.avm";
  return { name, bytes: new Uint8Array(await res.arrayBuffer()) };
}

export function appUrl(app: LoadedApp): string {
  // AtomVM picks .avm vs .beam with strrchr(path, '.') over the whole argument, so the URL must
  // end in ".avm". A blob URL (blob:https://host/uuid) has no suffix, so we append the app name as
  // a fragment ("#/clock.avm"): fetch never sends fragments, so the VM still downloads the blob,
  // while the suffix check sees ".avm".
  const blob = new Blob([app.bytes as BlobPart], { type: "application/octet-stream" });
  const name = app.name.endsWith(".avm") ? app.name : `${app.name}.avm`;
  return `${URL.createObjectURL(blob)}#/${name}`;
}

export const saveLastApp = (app: LoadedApp): Promise<void> => set(KEY, app);
export const loadLastApp = (): Promise<LoadedApp | undefined> => get<LoadedApp>(KEY);
