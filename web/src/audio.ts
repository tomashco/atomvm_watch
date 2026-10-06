/** Square-wave buzzer for m5_speaker tones. */
export class Buzzer {
  private ctx?: AudioContext; private osc?: OscillatorNode; private gain?: GainNode; private timer?: number;
  tone(freqHz: number, ms: number, volume0to255: number) {
    this.stop();
    this.ctx ??= new AudioContext();
    if (this.ctx.state === "suspended") void this.ctx.resume();
    this.osc = this.ctx.createOscillator(); this.gain = this.ctx.createGain();
    this.osc.type = "square"; this.osc.frequency.value = freqHz;
    this.gain.gain.value = 0.2 * (Math.max(0, Math.min(255, volume0to255)) / 255);
    this.osc.connect(this.gain).connect(this.ctx.destination); this.osc.start();
    if (ms > 0) this.timer = window.setTimeout(() => this.stop(), ms);
  }
  stop() {
    if (this.timer !== undefined) { clearTimeout(this.timer); this.timer = undefined; }
    this.osc?.stop(); this.osc?.disconnect(); this.gain?.disconnect();
    this.osc = undefined; this.gain = undefined;
  }
}
