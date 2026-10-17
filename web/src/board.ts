import Ajv from "ajv/dist/2020";
import schema from "../../boards/schema.json";
export interface BoardButton { id: "a" | "b" | "c" | "pwr" | "ext"; label: string; key: string; x: number; y: number }
export interface BoardProfile {
  id: string; name: string; boardAtom: string;
  screen: { width: number; height: number; scale: number; x: number; y: number };
  buttons: BoardButton[];
  peripherals: { speaker: boolean; led: boolean; battery: boolean };
  chip: string; firmwareManifest: string; appOffset: number; deviceImage: string;
}
const validate = new Ajv({ allErrors: true }).compile(schema);
export function parseBoardProfile(json: unknown): BoardProfile {
  if (!validate(json)) {
    const e = validate.errors![0];
    throw new Error(`invalid board profile at ${e.instancePath || "/"} (${e.message}) — ${JSON.stringify(validate.errors)}`);
  }
  return json as unknown as BoardProfile;
}
export async function loadBoardProfile(id: string, base = import.meta.env.BASE_URL): Promise<BoardProfile> {
  const res = await fetch(`${base}boards/${id}/board.json`);
  if (!res.ok) throw new Error(`board profile ${id} not found (${res.status})`);
  return parseBoardProfile(await res.json());
}
