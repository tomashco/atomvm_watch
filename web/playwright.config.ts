import { defineConfig } from "@playwright/test";

// End-to-end tests run the built page (vite preview keeps the COOP/COEP headers) in chromium.
// `prebuild` copies e2e/fixtures/*.avm into public/fixtures so the page can load them by URL.
export default defineConfig({
  testDir: "e2e",
  timeout: 60_000,
  forbidOnly: !!process.env.CI,
  webServer: {
    command: "pnpm build && pnpm preview --port 4173 --strictPort",
    port: 4173,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  use: { baseURL: "http://localhost:4173", browserName: "chromium" },
});
