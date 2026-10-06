import { defineConfig } from "vitest/config";
const coop = { "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" };
// The AtomVM release the page runs, from versions.env (devenv loads it; CI appends it to $GITHUB_ENV).
const atomvmVersion = process.env.ATOMVM_VERSION ?? "unknown";
export default defineConfig({
  base: "./",
  define: { __ATOMVM_VERSION__: JSON.stringify(atomvmVersion) },
  server: { headers: coop, fs: { allow: [".."] } },
  preview: { headers: coop },
  build: { target: "es2022" },
  test: { environment: "node", include: ["test/**/*.test.ts"] },
});
