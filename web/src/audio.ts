export type RawFormat = "u8" | "s8" | "s16";

/** Decode little-endian PCM bytes into one Float32Array (-1..1) per channel. Interleaved if stereo. */
export function decodePcm(bytes: Uint8Array, format: RawFormat, stereo: boolean): Float32Array<ArrayBuffer>[] {
  const channels = stereo ? 2 : 1;
  const bytesPerSample = format === "s16" ? 2 : 1;
  const frames = Math.floor(bytes.length / (bytesPerSample * channels));
  const out = Array.from({ length: channels }, () => new Float32Array(new ArrayBuffer(frames * 4)));
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  for (let f = 0; f < frames; f++) {
    for (let c = 0; c < channels; c++) {
      const i = (f * channels + c) * bytesPerSample;
      out[c][f] =
        format === "u8" ? (bytes[i] - 128) / 128 :
        format === "s8" ? view.getInt8(i) / 128 :
        view.getInt16(i, true) / 32768;
    }
  }
  return out;
}

const base64ToBytes = (b64: string) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const gainFor = (volume0to255: number) => Math.max(0, Math.min(255, volume0to255)) / 255;

/** m5_speaker: square-wave tones and raw PCM playback, one voice at a time like the emulator models it. */
export class Buzzer {
  private ctx?: AudioContext; private src?: AudioScheduledSourceNode; private gain?: GainNode; private timer?: number;

  private start(src: AudioScheduledSourceNode, gain: number, ms: number) {
    const ctx = this.ctx!;
    this.src = src; this.gain = ctx.createGain(); this.gain.gain.value = gain;
    src.connect(this.gain).connect(ctx.destination); src.start();
    if (ms > 0) this.timer = window.setTimeout(() => this.stop(), ms);
  }

  private context() {
    this.stop();
    this.ctx ??= new AudioContext();
    if (this.ctx.state === "suspended") void this.ctx.resume();
    return this.ctx;
  }

  tone(freqHz: number, ms: number, volume0to255: number) {
    const osc = this.context().createOscillator();
    osc.type = "square"; osc.frequency.value = freqHz;
    this.start(osc, 0.2 * gainFor(volume0to255), ms);
  }

  /** Raw PCM from m5_speaker:play_raw_*: base64 data, sample rate, stereo, repeat (0 = until stop). */
  playRaw(format: RawFormat, b64: string, rate: number, stereo: boolean, repeat: number, volume0to255: number) {
    const ctx = this.context();
    const chans = decodePcm(base64ToBytes(b64), format, stereo);
    if (chans[0].length === 0 || rate <= 0) return;
    const buf = ctx.createBuffer(chans.length, chans[0].length, rate);
    chans.forEach((d, c) => buf.copyToChannel(d, c));
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.loop = repeat !== 1;
    this.start(src, gainFor(volume0to255), repeat === 0 ? 0 : buf.duration * 1000 * repeat);
  }

  stop() {
    if (this.timer !== undefined) { clearTimeout(this.timer); this.timer = undefined; }
    this.src?.stop(); this.src?.disconnect(); this.gain?.disconnect();
    this.src = undefined; this.gain = undefined;
  }
}
