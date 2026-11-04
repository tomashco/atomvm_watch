import { test, expect } from "@playwright/test";

// The examples picker lists web/e2e/fixtures/examples.json and loads the chosen one like ?avm= does.
test("examples picker lists the fixtures and loads the chosen one", async ({ page }) => {
  await page.goto("/");
  const select = page.locator("#example");
  await expect(select.locator("option")).toHaveText(["Choose…", "clock", "scenes", "nyan", "gleam_hello", "gleam_scenes"]);
  await select.selectOption("nyan.avm");
  await expect(page).toHaveURL(/avm=\.\/fixtures\/nyan\.avm/);
  await expect(page.locator("#app-name")).toHaveText("nyan.avm", { timeout: 30_000 });
  await expect(select).toHaveValue("nyan.avm");
  await expect(page.locator("#example-info")).toContainText("rainbow");
});

// Without a mirrored runtimes list (local builds), the runtime picker offers the one published runtime.
test("runtime picker falls back to the published runtime", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("#runtime option")).toHaveText(["latest"]);
});
