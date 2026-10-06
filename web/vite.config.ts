import { defineConfig } from "vitest/config";
const coop = { "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" };
export default defineConfig({
  base: "./",
  server: { headers: coop, fs: { allow: [".."] } },
  preview: { headers: coop },
  build: { target: "es2022" },
  test: { environment: "node", include: ["test/**/*.test.ts"] },
});
