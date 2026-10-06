import { Framebuffer } from "./framebuffer";
import { FONT0, GLYPH_W, CELL_W, CELL_H } from "./font0";
import type { Command } from "./protocol";

const TEXT_FG = 0xffffff, TEXT_BG = 0x000000;

export class M5Renderer {
  readonly fb: Framebuffer;
  rotation = 0; cursor = { x: 0, y: 0 }; textSize = { x: 1, y: 1 };
  color = 0xffffff; baseColor = 0; sleeping = false; brightness = 128;
  onEvent?: (name: string, args: (number | string)[]) => void;
  private warned = new Set<string>();
  constructor(private nativeW: number, private nativeH: number) { this.fb = new Framebuffer(nativeW, nativeH); }

  width() { return this.rotation & 1 ? this.nativeH : this.nativeW; }
  height() { return this.rotation & 1 ? this.nativeW : this.nativeH; }

  // Logical -> native, M5GFX rotation convention (clockwise quarter turns).
  private plot(x: number, y: number, c: number) {
    const W = this.nativeW, H = this.nativeH;
    switch (this.rotation & 3) {
      case 0: this.fb.setPixel(x, y, c); break;
      case 1: this.fb.setPixel(W - 1 - y, x, c); break;
      case 2: this.fb.setPixel(W - 1 - x, H - 1 - y, c); break;
      case 3: this.fb.setPixel(y, H - 1 - x, c); break;
    }
  }
  private fillRect(x: number, y: number, w: number, h: number, c: number) {
    const x0 = Math.max(0, x), y0 = Math.max(0, y), x1 = Math.min(this.width(), x + w), y1 = Math.min(this.height(), y + h);
    for (let yy = y0; yy < y1; yy++) for (let xx = x0; xx < x1; xx++) this.plot(xx, yy, c);
  }
  private drawRect(x: number, y: number, w: number, h: number, c: number) {
    this.fillRect(x, y, w, 1, c); this.fillRect(x, y + h - 1, w, 1, c); this.fillRect(x, y, 1, h, c); this.fillRect(x + w - 1, y, 1, h, c);
  }
  // Liang-Barsky clip to the logical screen; null when nothing is visible. Endpoints are rounded to pixels.
  private clipLine(x0: number, y0: number, x1: number, y1: number): [number, number, number, number] | null {
    const xmax = this.width() - 1, ymax = this.height() - 1;
    const dx = x1 - x0, dy = y1 - y0;
    let t0 = 0, t1 = 1;
    for (const [p, q] of [[-dx, x0], [dx, xmax - x0], [-dy, y0], [dy, ymax - y0]]) {
      if (p === 0) { if (q < 0) return null; continue; }
      const t = q / p;
      if (p < 0) { if (t > t1) return null; if (t > t0) t0 = t; } else { if (t < t0) return null; if (t < t1) t1 = t; }
    }
    return [Math.round(x0 + t0 * dx), Math.round(y0 + t0 * dy), Math.round(x0 + t1 * dx), Math.round(y0 + t1 * dy)];
  }
  private line(x0: number, y0: number, x1: number, y1: number, c: number) { // Bresenham
    if (![x0, y0, x1, y1].every(Number.isFinite)) return; // short command: never loop on NaN
    if (Math.max(Math.abs(x0), Math.abs(y0), Math.abs(x1), Math.abs(y1)) > 8192) {
      const k = this.clipLine(x0, y0, x1, y1); if (!k) return; [x0, y0, x1, y1] = k;
    }
    let dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy;
    for (;;) { this.plot(x0, y0, c); if (x0 === x1 && y0 === y1) break; const e2 = 2 * err; if (e2 >= dy) { err += dy; x0 += sx; } if (e2 <= dx) { err += dx; y0 += sy; } }
  }
  private circle(cx: number, cy: number, r: number, c: number, fill: boolean) {
    if (r < 0) return;
    const ylo = Math.max(-r, -cy), yhi = Math.min(r, this.height() - 1 - cy);
    for (let y = ylo; y <= yhi; y++) {
      const half = Math.round(Math.sqrt(r * r - y * y));
      if (fill) this.fillRect(cx - half, cy + y, 2 * half + 1, 1, c);
      else { this.plot(cx - half, cy + y, c); this.plot(cx + half, cy + y, c); }
    }
    if (!fill) for (let x = Math.max(-r, -cx); x <= Math.min(r, this.width() - 1 - cx); x++) { const half = Math.round(Math.sqrt(r * r - x * x)); this.plot(cx + x, cy - half, c); this.plot(cx + x, cy + half, c); }
  }
  private ellipse(cx: number, cy: number, rx: number, ry: number, c: number, fill: boolean) {
    if (rx < 0 || ry < 0) return;
    if (ry === 0) { this.fillRect(cx - rx, cy, 2 * rx + 1, 1, c); return; }
    for (let y = Math.max(-ry, -cy); y <= Math.min(ry, this.height() - 1 - cy); y++) {
      const half = Math.round(rx * Math.sqrt(1 - (y * y) / (ry * ry)));
      if (fill) this.fillRect(cx - half, cy + y, 2 * half + 1, 1, c); else { this.plot(cx - half, cy + y, c); this.plot(cx + half, cy + y, c); }
    }
    if (!fill && rx > 0) for (let x = Math.max(-rx, -cx); x <= Math.min(rx, this.width() - 1 - cx); x++) {
      const half = Math.round(ry * Math.sqrt(1 - (x * x) / (rx * rx))); this.plot(cx + x, cy - half, c); this.plot(cx + x, cy + half, c);
    }
  }
  private roundRect(x: number, y: number, w: number, h: number, r: number, c: number, fill: boolean) {
    const cap = 4 * Math.ceil(Math.hypot(this.width(), this.height()));
    r = Math.max(0, Math.min(r, Math.floor(w / 2), Math.floor(h / 2), cap));
    if (fill) {
      this.fillRect(x + r, y, w - 2 * r, h, c);
      for (let yy = 0; yy < r; yy++) {
        const half = Math.round(Math.sqrt(r * r - (r - yy) * (r - yy)));
        this.fillRect(x + r - half, y + yy, half, 1, c); this.fillRect(x + w - r, y + yy, half, 1, c);
        this.fillRect(x + r - half, y + h - 1 - yy, half, 1, c); this.fillRect(x + w - r, y + h - 1 - yy, half, 1, c);
      }
      this.fillRect(x, y + r, r, h - 2 * r, c); this.fillRect(x + w - r, y + r, r, h - 2 * r, c);
    } else {
      this.fillRect(x + r, y, w - 2 * r, 1, c); this.fillRect(x + r, y + h - 1, w - 2 * r, 1, c);
      this.fillRect(x, y + r, 1, h - 2 * r, c); this.fillRect(x + w - 1, y + r, 1, h - 2 * r, c);
      for (let yy = 0; yy < r; yy++) {
        const half = Math.round(Math.sqrt(r * r - (r - yy) * (r - yy)));
        this.plot(x + r - half, y + yy, c); this.plot(x + w - 1 - r + half, y + yy, c);
        this.plot(x + r - half, y + h - 1 - yy, c); this.plot(x + w - 1 - r + half, y + h - 1 - yy, c);
      }
    }
  }
  private triangle(x0: number, y0: number, x1: number, y1: number, x2: number, y2: number, c: number, fill: boolean) {
    if (!fill) { this.line(x0, y0, x1, y1, c); this.line(x1, y1, x2, y2, c); this.line(x2, y2, x0, y0, c); return; }
    const ys = Math.max(0, Math.min(y0, y1, y2)), ye = Math.min(this.height() - 1, Math.max(y0, y1, y2));
    for (let y = ys; y <= ye; y++) {
      const xs: number[] = [];
      for (const [ax, ay, bx, by] of [[x0, y0, x1, y1], [x1, y1, x2, y2], [x2, y2, x0, y0]]) {
        if ((y >= ay && y < by) || (y >= by && y < ay)) xs.push(ax + ((y - ay) * (bx - ax)) / (by - ay));
      }
      if (xs.length >= 2) { const a = Math.round(Math.min(...xs)), b = Math.round(Math.max(...xs)); this.fillRect(a, y, b - a + 1, 1, c); }
    }
  }
  // cp is a Unicode code point. Font0 covers 0..255; anything else is drawn as a 5x7 outline box.
  private glyph(cp: number, x: number, y: number) {
    const { x: sx, y: sy } = this.textSize;
    const known = cp < 256;
    for (let col = 0; col < CELL_W; col++) {
      const bits = known && col < GLYPH_W ? FONT0[cp * GLYPH_W + col] : 0;
      for (let row = 0; row < CELL_H; row++) {
        const on = known
          ? row < 7 && ((bits >> row) & 1) === 1
          : col < GLYPH_W && row < 7 && (col === 0 || col === GLYPH_W - 1 || row === 0 || row === 6);
        this.fillRect(x + col * sx, y + row * sy, sx, sy, on ? TEXT_FG : TEXT_BG);
      }
    }
  }
  private drawString(s: string, x: number, y: number) {
    const cw = CELL_W * this.textSize.x;
    let i = 0;
    for (const c of s) this.glyph(c.codePointAt(0)!, x + i++ * cw, y);
  }
  private strLen(s: string) { let n = 0; for (const _ of s) n++; return n; }
  private print(s: string) {
    const cw = CELL_W * this.textSize.x, ch = CELL_H * this.textSize.y, W = this.width();
    for (const c of s) {
      if (c === "\n") { this.cursor = { x: 0, y: this.cursor.y + ch }; continue; }
      if (c === "\r") { this.cursor = { x: 0, y: this.cursor.y }; continue; }
      if (this.cursor.x + cw > W) this.cursor = { x: 0, y: this.cursor.y + ch };
      this.glyph(c.codePointAt(0)!, this.cursor.x, this.cursor.y);
      this.cursor = { x: this.cursor.x + cw, y: this.cursor.y };
    }
  }

  // M5GFX takes int32 coordinates: truncate numeric args once. Returns null (and warns once) for a
  // malformed command: non-finite numbers, or a string/number in the wrong place.
  private normalize(cmd: Command): Command | null {
    const [name, ...a] = cmd;
    if (name === "tone" || name === "stop_tone" || name === "led") return cmd;
    if (name === "set_text_size") {
      const f = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? Math.max(1, Math.round(v)) : 1);
      return [name, f(a[0]), f(a[1])];
    }
    const strFirst = name === "print" || name === "draw_string" || name === "draw_center_string" || name === "draw_right_string";
    const out: (number | string)[] = [];
    for (let i = 0; i < a.length; i++) {
      const v = a[i];
      if (strFirst && i === 0) { if (typeof v !== "string") return this.bad(name); out.push(v); continue; }
      if (typeof v !== "number" || !Number.isFinite(v)) return this.bad(name);
      out.push(Math.trunc(v));
    }
    return [name, ...out];
  }
  private bad(name: string): null {
    const key = "bad:" + name;
    if (!this.warned.has(key)) { this.warned.add(key); console.warn(`m5emu: skipped ${name} with invalid arguments`); }
    return null;
  }

  exec(cmds: Command[]) {
    for (const cmd of cmds) {
      const norm = this.normalize(cmd);
      if (!norm) continue;
      const [name, ...a] = norm;
      const n = a as number[];
      switch (name) {
        case "fill_screen": this.fillRect(0, 0, this.width(), this.height(), n[0]); break;
        case "fill_rect": this.fillRect(n[0], n[1], n[2], n[3], n[4]); break;
        case "draw_rect": this.drawRect(n[0], n[1], n[2], n[3], n[4]); break;
        case "draw_pixel": this.plot(n[0], n[1], n[2]); break;
        case "draw_fast_vline": this.fillRect(n[0], n[1], 1, n[2], n[3]); break;
        case "draw_fast_hline": this.fillRect(n[0], n[1], n[2], 1, n[3]); break;
        case "draw_line": this.line(n[0], n[1], n[2], n[3], n[4]); break;
        case "draw_circle": this.circle(n[0], n[1], n[2], n[3], false); break;
        case "fill_circle": this.circle(n[0], n[1], n[2], n[3], true); break;
        case "draw_ellipse": this.ellipse(n[0], n[1], n[2], n[3], n[4], false); break;
        case "fill_ellipse": this.ellipse(n[0], n[1], n[2], n[3], n[4], true); break;
        case "draw_round_rect": this.roundRect(n[0], n[1], n[2], n[3], n[4], n[5], false); break;
        case "fill_round_rect": this.roundRect(n[0], n[1], n[2], n[3], n[4], n[5], true); break;
        case "draw_triangle": this.triangle(n[0], n[1], n[2], n[3], n[4], n[5], n[6], false); break;
        case "fill_triangle": this.triangle(n[0], n[1], n[2], n[3], n[4], n[5], n[6], true); break;
        case "draw_string": this.drawString(String(a[0]), n[1], n[2]); break;
        case "draw_center_string": { const s = String(a[0]); this.drawString(s, n[1] - Math.floor((this.strLen(s) * CELL_W * this.textSize.x) / 2), n[2]); break; }
        case "draw_right_string": { const s = String(a[0]); this.drawString(s, n[1] - this.strLen(s) * CELL_W * this.textSize.x, n[2]); break; }
        case "print": this.print(String(a[0])); break;
        case "println": this.print("\n"); break;
        case "set_cursor": this.cursor = { x: n[0], y: n[1] }; break;
        case "set_text_size": this.textSize = { x: n[0], y: n[1] }; break;
        case "set_color": this.color = n[0]; break;
        case "set_base_color": this.baseColor = n[0]; break;
        case "set_rotation": this.rotation = n[0] & 3; break;
        case "set_brightness": this.brightness = n[0]; break;
        case "sleep": this.sleeping = true; break;
        case "wakeup": this.sleeping = false; break;
        case "tone": case "stop_tone": case "led": this.onEvent?.(name, a); break;
        default:
          if (!this.warned.has(name)) { this.warned.add(name); console.warn(`m5emu: unsupported command ${name}`); }
      }
    }
  }
}
