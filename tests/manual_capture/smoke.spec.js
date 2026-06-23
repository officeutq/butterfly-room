const fs = require("node:fs");
const path = require("node:path");
const { expect, test } = require("@playwright/test");

const SCREENSHOT_DIR = path.resolve(__dirname, "../../docs/user_manual/images/smoke");
const PASSWORD = "ManualCapture123!";
const FULL_PAGE = process.env.MANUAL_CAPTURE_FULL_PAGE === "1";

const accounts = [
  {
    name: "customer_dashboard",
    email: "manual+customer@example.test",
    expectedText: "プロフィール編集",
  },
  {
    name: "store_admin_dashboard",
    email: "manual+store_admin@example.test",
    expectedText: "ブース管理",
  },
  {
    name: "cast_dashboard",
    email: "manual+cast@example.test",
    expectedText: "ブース情報",
  },
  {
    name: "system_admin_dashboard",
    email: "manual+system_admin@example.test",
    expectedText: "ユーザー管理",
  },
];

test.beforeAll(() => {
  fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
});

async function gotoAndSettle(page, url) {
  await page.goto(url, { waitUntil: "domcontentloaded" });
  await page.waitForLoadState("networkidle", { timeout: 5_000 }).catch(() => {});
}

async function capture(page, filename) {
  await page.screenshot({
    path: path.join(SCREENSHOT_DIR, `${filename}.png`),
    fullPage: FULL_PAGE,
  });
}

async function login(page, email) {
  await gotoAndSettle(page, "/users/sign_in");
  await page.locator('input[name="user[email]"]').fill(email);
  await page.locator('input[name="user[password]"]').fill(PASSWORD);
  await Promise.all([
    page.waitForURL((url) => !url.pathname.includes("/users/sign_in")),
    page.locator('input[type="submit"]').click(),
  ]);
  await page.waitForLoadState("networkidle", { timeout: 5_000 }).catch(() => {});
}

test("guest home", async ({ page }) => {
  await gotoAndSettle(page, "/");

  await expect(page.locator("body")).toContainText("Butterflyve");
  await capture(page, "guest_home");
});

test("login page", async ({ page }) => {
  await gotoAndSettle(page, "/users/sign_in");

  await expect(page.locator("body")).toContainText("ログイン");
  await capture(page, "login");
});

for (const account of accounts) {
  test(`${account.name}`, async ({ page }) => {
    await login(page, account.email);
    await gotoAndSettle(page, "/dashboard");

    await expect(page).toHaveURL(/\/dashboard/);
    await expect(page.locator("body")).toContainText(account.expectedText);
    await capture(page, account.name);
  });
}
