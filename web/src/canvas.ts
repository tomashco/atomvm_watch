import type { M5Renderer } from "./renderer";
export function attachCanvas(r: M5Renderer, canvas: HTMLCanvasElement) {
  const ctx = canvas.getContext("2d")!;
  let image = ctx.createImageData(r.fb.width, r.fb.height);
  return {
    present() {
      if (canvas.width !== r.fb.width || canvas.height !== r.fb.height) {
        canvas.width = r.fb.width; canvas.height = r.fb.height; image = ctx.createImageData(r.fb.width, r.fb.height);
      }
      // A sleeping panel is dark, like the real LCD: paint opaque black and keep the framebuffer,
      // so wakeup shows the previous contents again.
      if (r.sleeping) {
        ctx.fillStyle = "#000"; ctx.fillRect(0, 0, canvas.width, canvas.height);
        canvas.style.filter = "";
        return;
      }
      image.data.set(r.fb.toRGBA());
      ctx.putImageData(image, 0, 0);
      // Backlight level dims the pixels toward black; the panel itself stays opaque, so nothing
      // behind the canvas (the device image) ever shows through.
      canvas.style.filter = `brightness(${0.25 + 0.75 * (r.brightness / 255)})`;
    },
  };
}
