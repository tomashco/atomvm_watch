import { describe, it, expect } from "vitest";
import { buttonMessage, batteryMessage, boardMessage } from "../src/protocol";
import { parseBoardProfile } from "../src/board";
import { readFileSync } from "node:fs";
const p = parseBoardProfile(JSON.parse(readFileSync(new URL("../../boards/m5stickc_plus2/board.json", import.meta.url), "utf8")));
describe("protocol", () => {
  it("formats button events", () => {
    expect(buttonMessage("a", true)).toBe("a:down");
    expect(buttonMessage("pwr", false)).toBe("pwr:up");
  });
  it("clamps battery", () => {
    expect(batteryMessage(73)).toBe("batt:73");
    expect(batteryMessage(140)).toBe("batt:100");
    expect(batteryMessage(-3)).toBe("batt:0");
  });
  it("formats the board handshake", () => {
    expect(boardMessage(p)).toBe("board:stick_cplus2:135:240");
  });
});
