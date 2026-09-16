const fs = require("node:fs");
const path = require("node:path");
const { expect } = require("@playwright/test");

const PRIMARY_STORE = "マニュアル撮影用店舗";
const PRIMARY_BOOTH = "マニュアル撮影用ブース";
const SECONDARY_BOOTH = "マニュアル撮影用サブブース";

async function openSelection(page, kind) {
  const href = kind === "store" ? "/admin/stores/select_modal" : "/cast/booths/select_modal";
  if (!(await page.locator("header .dropdown-menu").isVisible())) {
    await page.locator('header [data-bs-toggle="dropdown"]').click();
  }
  await page.locator(`header a[href*="${href}"]`).click();
  const modal = page.locator("#modal .modal.show");
  await expect(modal).toBeVisible();
  return modal;
}

async function choose(page, modal, name) {
  const row = modal.locator(".list-group-item").filter({ hasText: name });
  await expect(row).toHaveCount(1);
  const id = await row.locator('input[name="booth_id"], input[name="store_id"]').inputValue();
  await Promise.all([
    page.waitForResponse((response) => response.request().method() === "POST" &&
      /\/(cast\/current_booth|admin\/current_store)$/.test(new URL(response.url()).pathname)),
    row.getByRole("button", { name: /切り替え|切替/ }).click(),
  ]);
  await expect(page.locator("#modal .modal.show")).toHaveCount(0);
  await expect(page.locator("header")).toContainText(name);
  return id;
}

async function selectPrimaryStore(page) {
  await page.goto("/dashboard");
  await choose(page, await openSelection(page, "store"), PRIMARY_STORE);
}

async function captureSelection(page, role, root) {
  // This flow must use the separately started test server, never the development app.
  const base = new URL(page.url());
  if (!["127.0.0.1", "localhost"].includes(base.hostname) || base.port !== "3102") {
    throw new Error("Selection capture requires the isolated local server on port 3102. See selection_capture.md.");
  }
  await page.setViewportSize({ width: 1440, height: 1400 });
  const directory = path.join(root, "selection");
  fs.mkdirSync(directory, { recursive: true });
  const capture = async (filename) => {
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(directory, filename), fullPage: true, animations: "disabled" });
  };

  await page.goto("/dashboard");
  if (role !== "cast") {
    const stores = await openSelection(page, "store");
    await capture("02_store_modal.png");
    await choose(page, stores, PRIMARY_STORE);
  }
  const booths = await openSelection(page, "booth");
  await expect(booths).toContainText(SECONDARY_BOOTH);
  if (role !== "cast") await expect(booths).toContainText("閉鎖済み");
  await capture("03_booth_modal.png");
  const id = await choose(page, booths, PRIMARY_BOOTH);
  await page.locator('header [data-bs-toggle="dropdown"]').click();
  await capture("01_dashboard.png");
  await page.locator('header [data-bs-toggle="dropdown"]').click();

  // The obsolete cast list URL no longer offers another selection surface.
  await page.goto("/cast/booths");
  await expect(page).toHaveURL(/\/dashboard$/);
  await page.goto(`/cast/booths/${id}`);
  await expect(page.getByRole("link", { name: "配信履歴", exact: true })).toBeVisible();
  await capture("04_information.png");
  await page.getByRole("link", { name: "編集", exact: true }).click();
  await expect(page.locator('input[name="booth[name]"]')).toHaveValue(PRIMARY_BOOTH);
  await capture("05_edit.png");
  await page.goto(`/cast/booths/${id}/stream_sessions`);
  await expect(page.locator("body")).toContainText("配信履歴");
  await capture("06_history.png");

  await page.goto(`/cast/booths/${id}`);
  const nextId = await choose(page, await openSelection(page, "booth"), SECONDARY_BOOTH);
  await expect(page).toHaveURL(new RegExp(`/cast/booths/${nextId}$`));
  await expect(page.locator("main")).toContainText(SECONDARY_BOOTH);
  await capture("07_information_switched.png");
}

module.exports = { captureSelection, openSelection, selectPrimaryStore };
