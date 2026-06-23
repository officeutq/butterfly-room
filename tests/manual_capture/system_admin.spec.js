const fs = require("node:fs");
const path = require("node:path");
const { expect, test } = require("@playwright/test");

const BASE_URL =
  process.env.MANUAL_CAPTURE_BASE_URL ||
  process.env.PLAYWRIGHT_BASE_URL ||
  "http://127.0.0.1:3000";
const SCREENSHOT_ROOT = path.resolve(__dirname, "../../docs/user_manual/images/system_admin");
const PASSWORD = "ManualCapture123!";
const RUN_ID =
  process.env.MANUAL_CAPTURE_RUN_ID ||
  new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const RUN_SLUG = RUN_ID.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 24) || "local";
const FULL_PAGE = process.env.MANUAL_CAPTURE_FULL_PAGE !== "0";

const sections = [
  "dashboard",
  "users",
  "referral_codes",
  "notifications",
  "effects",
  "admin_stores",
  "store_bans",
  "settlements",
  "settlement_exports",
  "manual_settlements",
];

const createdRecords = {
  userEmail: `manual+system_admin_capture_user_${RUN_SLUG}@example.test`,
  referralCode: `MANUAL-SYSTEM-ADMIN-${RUN_SLUG.toUpperCase()}`,
  notificationTitle: `マニュアル撮影用お知らせ ${RUN_SLUG}`,
  effectName: `マニュアル撮影用 Effect ${RUN_SLUG}`,
  effectKey: `manual_system_admin_${RUN_SLUG}`,
};

test.describe.configure({ mode: "serial" });
test.setTimeout(180_000);

test.beforeAll(() => {
  assertLocalBaseUrl();

  for (const section of sections) {
    const dir = path.join(SCREENSHOT_ROOT, section);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
  }

  console.log(`manual system_admin capture run id: ${RUN_ID}`);
  console.log(`manual system_admin capture user: ${createdRecords.userEmail}`);
  console.log(`manual system_admin referral code: ${createdRecords.referralCode}`);
});

function assertLocalBaseUrl() {
  if (process.env.MANUAL_CAPTURE_ALLOW_REMOTE === "1") return;

  const hostname = new URL(BASE_URL).hostname;
  const allowed = ["127.0.0.1", "localhost", "[::1]"];

  if (!allowed.includes(hostname)) {
    throw new Error(
      `manual system_admin capture is local-only. Set MANUAL_CAPTURE_ALLOW_REMOTE=1 to override. baseURL=${BASE_URL}`
    );
  }
}

function appUrl(pathOrUrl) {
  if (/^https?:\/\//.test(pathOrUrl)) return pathOrUrl;

  return new URL(pathOrUrl, BASE_URL).toString();
}

async function settle(page) {
  await page.waitForLoadState("domcontentloaded").catch(() => {});
  await page.waitForLoadState("networkidle", { timeout: 5_000 }).catch(() => {});
}

async function gotoAndSettle(page, pathOrUrl) {
  await page.goto(appUrl(pathOrUrl), { waitUntil: "domcontentloaded" });
  await settle(page);
}

async function capture(page, section, filename) {
  await page.screenshot({
    path: path.join(SCREENSHOT_ROOT, section, filename),
    fullPage: FULL_PAGE,
  });
}

async function submitAndSettle(page, selector) {
  await page.locator(selector).first().click();
  await settle(page);
}

async function submitAndWaitForURL(page, selector, urlMatcher) {
  await Promise.all([
    page.waitForURL(urlMatcher, { timeout: 20_000 }),
    page.locator(selector).first().click(),
  ]);
  await settle(page);
}

async function loginAsSystemAdmin(page) {
  await gotoAndSettle(page, "/users/sign_in");
  await page.locator('input[name="user[email]"]').fill("manual+system_admin@example.test");
  await page.locator('input[name="user[password]"]').fill(PASSWORD);
  await submitAndWaitForURL(
    page,
    'form input[type="submit"], form button[type="submit"]',
    (url) => !url.pathname.includes("/users/sign_in")
  );
}

async function selectPrimaryManualStore(page) {
  await gotoAndSettle(page, "/admin/stores");
  await expect(page).toHaveURL(/\/admin\/stores/);
  await expect(page.locator("body")).toContainText("店舗名");
  await expect(page.locator("body")).toContainText("マニュアル撮影用店舗");
  await capture(page, "admin_stores", "01_store_select.png");

  const primaryRow = page
    .locator("tr")
    .filter({ has: page.locator("td", { hasText: /^マニュアル撮影用店舗$/ }) })
    .first();
  await expect(primaryRow).toBeVisible();
  await Promise.all([
    page.waitForURL(/\/dashboard/, { timeout: 20_000 }),
    primaryRow.locator('input[type="submit"], button[type="submit"]').first().click(),
  ]);
  await settle(page);
  await capture(page, "admin_stores", "02_after_store_select_dashboard.png");
}

async function fillManualSettlementPeriod(page) {
  const day = (Number.parseInt(RUN_SLUG.slice(-2), 10) || 1) % 20 + 1;
  const nextDay = day + 1;
  const periodFrom = `2036-01-${String(day).padStart(2, "0")}T00:00`;
  const periodTo = `2036-01-${String(nextDay).padStart(2, "0")}T00:00`;

  const storeSelect = page.locator('select[name="manual_settlement[store_id]"]');
  await storeSelect.selectOption({ label: "マニュアル撮影用店舗" });
  await page.locator('input[name="manual_settlement[period_from]"]').fill(periodFrom);
  await page.locator('input[name="manual_settlement[period_to]"]').fill(periodTo);
}

async function fillDateTimeWithExistingSeconds(locator, valueWithoutSeconds) {
  const currentValue = await locator.inputValue();
  const seconds = currentValue.match(/:(\d{2})$/)?.[1] || "00";
  await locator.fill(`${valueWithoutSeconds}:${seconds}`);
}

async function fillFirstNonPromptOption(page, selector) {
  const select = page.locator(selector);
  if ((await select.count()) === 0) return false;

  const optionCount = await select.locator("option").count();
  if (optionCount <= 1) return false;

  await select.selectOption({ index: 1 });
  return true;
}

test("system_admin normal operation screenshots", async ({ page }) => {
  await loginAsSystemAdmin(page);
  await selectPrimaryManualStore(page);

  await gotoAndSettle(page, "/dashboard");
  await expect(page).toHaveURL(/\/dashboard/);
  await expect(page.locator("body")).toContainText("ユーザー管理");
  await expect(page.locator("body")).toContainText("紹介コード管理");
  await expect(page.locator("body")).toContainText("お知らせ管理");
  await expect(page.locator("body")).toContainText("Effect管理");
  await expect(page.locator("body")).toContainText("店舗BAN");
  await capture(page, "dashboard", "01_dashboard.png");

  await gotoAndSettle(page, "/system_admin/users");
  await expect(page).toHaveURL(/\/system_admin\/users/);
  await expect(page.locator("h1")).toContainText("ユーザー管理");
  await capture(page, "users", "01_index.png");

  await gotoAndSettle(page, "/system_admin/users/new");
  await expect(page.locator("h1")).toContainText("ユーザー作成");
  await expect(page.locator('select[name="user[role]"]')).toBeVisible();
  await capture(page, "users", "02_new_form.png");

  await page.locator('input[name="user[email]"]').fill(createdRecords.userEmail);
  await page.locator('select[name="user[role]"]').selectOption("customer");
  await page.locator('input[name="user[password]"]').fill(PASSWORD);
  await page.locator('input[name="user[password_confirmation]"]').fill(PASSWORD);
  await capture(page, "users", "03_filled.png");

  await submitAndWaitForURL(
    page,
    'form[action="/system_admin/users"] input[type="submit"], form[action="/system_admin/users"] button[type="submit"]',
    (url) => url.pathname === "/system_admin/users"
  );
  await expect(page.locator("body")).toContainText("ユーザーを作成しました");
  await expect(page.locator("body")).toContainText(createdRecords.userEmail);
  await capture(page, "users", "04_after_save.png");

  await gotoAndSettle(page, "/system_admin/referral_codes");
  await expect(page).toHaveURL(/\/system_admin\/referral_codes/);
  await expect(page.locator("h1")).toContainText("紹介コード管理");
  await capture(page, "referral_codes", "01_index.png");

  await gotoAndSettle(page, "/system_admin/referral_codes/new");
  await expect(page.locator("h1")).toContainText("紹介コード作成");
  await capture(page, "referral_codes", "02_new_form.png");

  await page.locator('input[name="referral_code[code]"]').fill(createdRecords.referralCode);
  await page.locator('input[name="referral_code[label]"]').fill(`マニュアル撮影用 ${RUN_SLUG}`);
  await page.locator('input[name="referral_code[expires_at]"]').fill("2027-12-31T23:59");
  await page.locator('input[type="checkbox"][name="referral_code[enabled]"]').check();
  await capture(page, "referral_codes", "03_filled.png");

  await submitAndWaitForURL(
    page,
    'form[action="/system_admin/referral_codes"] input[type="submit"], form[action="/system_admin/referral_codes"] button[type="submit"]',
    (url) => url.pathname === "/system_admin/referral_codes"
  );
  await expect(page.locator("body")).toContainText("紹介コードを作成しました");
  await expect(page.locator("body")).toContainText(createdRecords.referralCode);
  await capture(page, "referral_codes", "04_after_save.png");

  await gotoAndSettle(page, "/system_admin/notifications");
  await expect(page).toHaveURL(/\/system_admin\/notifications/);
  await expect(page.locator("h1")).toContainText("お知らせ管理");
  await capture(page, "notifications", "01_index.png");

  await gotoAndSettle(page, "/system_admin/notifications/new");
  await expect(page.locator("h1")).toContainText("お知らせ作成");
  await capture(page, "notifications", "02_new_form.png");

  await page.locator('input[name="notification[title]"]').fill(createdRecords.notificationTitle);
  await page
    .locator('textarea[name="notification[body]"]')
    .fill("system_admin（運営）通常操作撮影で作成したお知らせ本文です。実ユーザー向け告知ではありません。");
  await fillDateTimeWithExistingSeconds(
    page.locator('input[name="notification[published_at]"]'),
    "2026-06-23T10:00"
  );
  await page.locator('input[type="checkbox"][name="notification[enabled]"]').check();
  await page
    .locator('textarea[name="notification[new_tag_names]"]')
    .fill(`manual\nsystem_admin_capture_${RUN_SLUG}`);
  await capture(page, "notifications", "03_filled.png");

  await submitAndWaitForURL(
    page,
    'form[action="/system_admin/notifications"] input[type="submit"], form[action="/system_admin/notifications"] button[type="submit"]',
    (url) => url.pathname === "/system_admin/notifications"
  );
  await expect(page.locator("body")).toContainText("お知らせを作成しました");
  await expect(page.locator("body")).toContainText(createdRecords.notificationTitle);
  await capture(page, "notifications", "04_after_save.png");

  await gotoAndSettle(page, "/system_admin/effects");
  await expect(page).toHaveURL(/\/system_admin\/effects/);
  await expect(page.locator("h1")).toContainText("Effect管理");
  await capture(page, "effects", "01_index.png");

  await gotoAndSettle(page, "/system_admin/effects/new");
  await expect(page.locator("h1")).toContainText("Effect作成");
  await capture(page, "effects", "02_new_form.png");

  await page.locator('input[name="effect[name]"]').fill(createdRecords.effectName);
  await page.locator('input[name="effect[key]"]').fill(createdRecords.effectKey);
  await page.locator('input[name="effect[zip_filename]"]').fill(`${createdRecords.effectKey}.zip`);
  await page.locator('input[name="effect[icon_path]"]').fill(`/manual_capture/effects/${createdRecords.effectKey}.png`);
  await page.locator('input[name="effect[position]"]').fill("999");
  await page.locator('input[type="checkbox"][name="effect[enabled]"]').check();
  await capture(page, "effects", "03_filled.png");

  await submitAndWaitForURL(
    page,
    'form[action="/system_admin/effects"] input[type="submit"], form[action="/system_admin/effects"] button[type="submit"]',
    (url) => url.pathname === "/system_admin/effects"
  );
  await expect(page.locator("body")).toContainText("Effectを作成しました");
  await expect(page.locator("body")).toContainText(createdRecords.effectName);
  await capture(page, "effects", "04_after_save.png");

  await gotoAndSettle(page, "/admin/store_bans");
  await expect(page).toHaveURL(/\/admin\/store_bans/);
  await expect(page.locator("body")).toContainText("BAN対象");
  await capture(page, "store_bans", "01_index.png");
  await fillFirstNonPromptOption(page, 'select[name="store_ban[customer_user_id]"]');
  await page.locator('input[name="store_ban[reason]"]').fill("マニュアル撮影用の入力例です。BAN作成は実行しません。");
  await capture(page, "store_bans", "02_form_filled_not_submitted.png");

  await gotoAndSettle(page, "/system_admin/settlements");
  await expect(page).toHaveURL(/\/system_admin\/settlements/);
  await expect(page.locator("h1")).toContainText("精算一覧");
  await capture(page, "settlements", "01_index.png");

  const settlementDetailLinks = page.locator('a:has-text("詳細")');
  if ((await settlementDetailLinks.count()) > 0) {
    await Promise.all([
      page.waitForURL(/\/system_admin\/settlements\/\d+/, { timeout: 20_000 }),
      settlementDetailLinks.first().click(),
    ]);
    await settle(page);
    await expect(page.locator("h1")).toContainText("精算詳細");
    await capture(page, "settlements", "02_show.png");
  }

  await gotoAndSettle(page, "/system_admin/settlement_exports");
  await expect(page).toHaveURL(/\/system_admin\/settlement_exports/);
  await expect(page.locator("h1")).toContainText("振込CSV");
  await capture(page, "settlement_exports", "01_index.png");

  const exportDetailLinks = page.locator('a:has-text("詳細")');
  if ((await exportDetailLinks.count()) > 0) {
    await Promise.all([
      page.waitForURL(/\/system_admin\/settlement_exports\/\d+/, { timeout: 20_000 }),
      exportDetailLinks.first().click(),
    ]);
    await settle(page);
    await expect(page.locator("h1")).toContainText("振込CSV 詳細");
    await capture(page, "settlement_exports", "02_show.png");
  }

  await gotoAndSettle(page, "/system_admin/settlements/manual/new");
  await expect(page.locator("h1")).toContainText("マニュアル精算");
  await capture(page, "manual_settlements", "01_manual_form.png");

  await fillManualSettlementPeriod(page);
  await capture(page, "manual_settlements", "02_manual_filled.png");

  await submitAndSettle(
    page,
    'form[action="/system_admin/settlements/manual/preview"] input[type="submit"], form[action="/system_admin/settlements/manual/preview"] button[type="submit"]'
  );
  await expect(page.locator("body")).toContainText("プレビュー");
  await expect(page.locator("body")).toContainText("gross_yen");
  await capture(page, "manual_settlements", "03_manual_preview.png");
});
