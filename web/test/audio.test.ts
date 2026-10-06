import { describe, expect, it } from "vitest";
import { decodePcm } from "../src/audio";

describe("decodePcm", () => {
  it("u8 is offset binary around 128", () => {
    const [ch] = decodePcm(Uint8Array.from([0, 128, 255]), "u8", false);
    expect(Array.from(ch)).toEqual([-1, 0, 127 / 128]);
  });
  it("s8 is two's complement", () => {
    const [ch] = decodePcm(Uint8Array.from([0x80, 0x00, 0x7f]), "s8", false);
    expect(Array.from(ch)).toEqual([-1, 0, 127 / 128]);
  });
  it("s16 is little-endian and stereo is interleaved", () => {
    // frames: (L=-32768, R=16384), (L=0, R=-1)
    const bytes = Uint8Array.from([0x00, 0x80, 0x00, 0x40, 0x00, 0x00, 0xff, 0xff]);
    const [l, r] = decodePcm(bytes, "s16", true);
    expect(Array.from(l)).toEqual([-1, 0]);
    expect(Array.from(r)).toEqual([0.5, -1 / 32768]);
  });
  it("drops a trailing partial frame", () => {
    const [l, r] = decodePcm(Uint8Array.from([1, 2, 3]), "u8", true);
    expect(l.length).toBe(1);
    expect(r.length).toBe(1);
  });
});
