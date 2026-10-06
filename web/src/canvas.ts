import type { M5Renderer } from "./renderer";
export function attachCanvas(r: M5Renderer, canvas: HTMLCanvasElement) {
  const ctx = canvas.getContext("2d")!;
  let image = ctx.createImageData(r.fb.width, r.fb.height);
  return {
    present() {
      if (canvas.width !== r.fb.width || canvas.height !== r.fb.height) {
        canvas.width = r.fb.width; canvas.height = r.fb.height; image = ctx.createImageData(r.fb.width, r.fb.height);
      }
      image.data.set(r.fb.toRGBA());
      ctx.putImageData(image, 0, 0);
      canvas.style.opacity = r.sleeping ? "0" : String(0.25 + 0.75 * (r.brightness / 255));
    },
  };
}
