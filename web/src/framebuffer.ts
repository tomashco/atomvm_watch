export class Framebuffer {
  private px: Uint32Array;
  constructor(public readonly width: number, public readonly height: number) { this.px = new Uint32Array(width * height); }
  fill(rgb: number) { this.px.fill(rgb & 0xffffff); }
  setPixel(x: number, y: number, rgb: number) {
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return;
    this.px[y * this.width + x] = rgb & 0xffffff;
  }
  getPixel(x: number, y: number): number { return this.px[y * this.width + x]; }
  toRGBA(): Uint8ClampedArray {
    const out = new Uint8ClampedArray(this.width * this.height * 4);
    for (let i = 0; i < this.px.length; i++) {
      const c = this.px[i]; out[i * 4] = c >> 16; out[i * 4 + 1] = (c >> 8) & 0xff; out[i * 4 + 2] = c & 0xff; out[i * 4 + 3] = 255;
    }
    return out;
  }
}
