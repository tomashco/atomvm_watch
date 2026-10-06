import type { BoardProfile } from "./board";
export type Command = [string, ...(number | string)[]];
export const INPUT_PROCESS = "m5_emu_input";
export function buttonMessage(id: string, down: boolean): string { return `${id}:${down ? "down" : "up"}`; }
export function batteryMessage(percent: number): string {
  const p = Math.max(0, Math.min(100, Math.round(percent)));
  return `batt:${p}`;
}
export function boardMessage(p: BoardProfile): string { return `board:${p.boardAtom}:${p.screen.width}:${p.screen.height}`; }
