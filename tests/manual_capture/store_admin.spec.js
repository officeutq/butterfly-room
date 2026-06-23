const fs = require("node:fs");
const path = require("node:path");
const { expect, test } = require("@playwright/test");

const BASE_URL =
  process.env.MANUAL_CAPTURE_BASE_URL ||
  process.env.PLAYWRIGHT_BASE_URL ||
  "http://127.0.0.1:3000";
const SCREENSHOT_ROOT = path.resolve(__dirname, "../../docs/user_manual/images/store_admin");
const PASSWORD = "ManualCapture123!";
const RUN_ID =
  process.env.MANUAL_CAPTURE_RUN_ID ||
  new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const RUN_SLUG = RUN_ID.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 24) || "local";
const FULL_PAGE = process.env.MANUAL_CAPTURE_FULL_PAGE !== "0";

const sections = [
  "dashboard",
  "stores",
  "booths",
  "casts",
  "invitations",
  "drink_items",
  "metrics",
  "comment_reports",
  "payout_account",
  "settlements",
];

test.describe.configure({ mode: "serial" });
test.setTimeout(180_000);

test.beforeAll(() => {
  for (const section of sections) {
    const dir = path.join(SCREENSHOT_ROOT, section);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
  }

  console.log(`manual store_admin capture run id: ${RUN_ID}`);
});

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

async function loginAsStoreAdmin(page) {
  await gotoAndSettle(page, "/users/sign_in");
  await page.locator('input[name="user[email]"]').fill("manual+store_admin@example.test");
  await page.locator('input[name="user[password]"]').fill(PASSWORD);
  await submitAndWaitForURL(
    page,
    'form input[type="submit"], form button[type="submit"]',
    (url) => !url.pathname.includes("/users/sign_in")
  );
}

async function selectPrimaryManualStore(page) {
  await gotoAndSettle(page, "/admin/stores");
  const primaryRow = page.locator("tr", { hasText: "マニュアル撮影用店舗" }).first();
  await expect(primaryRow).toBeVisible();
  await Promise.all([
    page.waitForURL(/\/dashboard/, { timeout: 20_000 }),
    primaryRow.locator('input[type="submit"], button[type="submit"]').first().click(),
  ]);
  await settle(page);
}

test("store_admin normal operation screenshots", async ({ page }) => {
  await loginAsStoreAdmin(page);
  await selectPrimaryManualStore(page);

  await gotoAndSettle(page, "/dashboard");
  await expect(page).toHaveURL(/\/dashboard/);
  await expect(page.locator("body")).toContainText("ブース管理");
  await capture(page, "dashboard", "01_dashboard.png");

  await gotoAndSettle(page, "/admin/stores");
  await expect(page).toHaveURL(/\/admin\/stores/);
  await expect(page.locator("body")).toContainText("マニュアル撮影用サブ店舗");
  await capture(page, "stores", "01_index.png");

  await gotoAndSettle(page, "/dashboard");
  await submitAndWaitForURL(
    page,
    'a:has-text("店舗設定編集")',
    /\/admin\/stores\/\d+\/edit/
  );
  await expect(page.locator('input[name="store[name]"]')).toBeVisible();
  await capture(page, "stores", "02_edit_form.png");

  const updatedStoreName = `マニュアル撮影用店舗 ${RUN_SLUG}`;
  await page.locator('input[name="store[name]"]').fill(updatedStoreName);
  await page
    .locator('textarea[name="store[description]"]')
    .fill("マニュアル撮影用の店舗情報編集画面です。実店舗情報ではありません。");
  await page.locator('input[name="store[area]"]').fill("マニュアル撮影用エリア");
  await page.locator('select[name="store[business_type]"]').selectOption("girls_bar");
  await page.locator('input[name="store[phone_number]"]').fill("03-0000-0100");
  await page.locator('input[name="store[business_hours]"]').fill("20:00-25:00");
  await page.locator('input[name="store[website_url]"]').fill("https://example.test/manual-store");
  await capture(page, "stores", "03_edit_filled.png");

  await submitAndWaitForURL(
    page,
    'form[action*="/admin/stores/"] input[type="submit"], form[action*="/admin/stores/"] button[type="submit"]',
    /\/dashboard/
  );
  await expect(page.locator("body")).toContainText("店舗情報を更新しました");
  await capture(page, "stores", "04_after_update_dashboard.png");

  await gotoAndSettle(page, "/admin/booths");
  await expect(page).toHaveURL(/\/admin\/booths/);
  await expect(page.locator("body")).toContainText("ブース管理");
  await capture(page, "booths", "01_index.png");

  await gotoAndSettle(page, "/admin/booths/new");
  await expect(page.locator('input[name="booth[name]"]')).toBeVisible();
  await capture(page, "booths", "02_new_form.png");

  const boothName = `マニュアル撮影用ブース ${RUN_SLUG}`;
  await page.locator('input[name="booth[name]"]').fill(boothName);
  await page
    .locator('textarea[name="booth[description]"]')
    .fill("store_admin 通常操作撮影で作成したブースです。AWS IVS は疑似 ARN を使います。");
  const castSelect = page.locator('select[name="booth_cast[cast_user_id]"]');
  if ((await castSelect.count()) > 0) {
    const options = await castSelect.locator("option").count();
    if (options > 1) {
      await castSelect.selectOption({ index: 1 });
    }
  }
  await capture(page, "booths", "03_new_filled.png");

  await submitAndWaitForURL(
    page,
    'form[action="/admin/booths"] input[type="submit"], form[action="/admin/booths"] button[type="submit"]',
    /\/dashboard/
  );
  await expect(page.locator("body")).toContainText("ブースを作成しました");
  await capture(page, "booths", "04_after_create_dashboard.png");

  await gotoAndSettle(page, "/admin/booths");
  await expect(page.locator("body")).toContainText(boothName);
  await capture(page, "booths", "05_index_after_create.png");

  await gotoAndSettle(page, "/admin/casts");
  await expect(page).toHaveURL(/\/admin\/casts/);
  await expect(page.locator("body")).toContainText("キャスト招待");
  await capture(page, "casts", "01_index.png");

  await gotoAndSettle(page, "/admin/cast_invitations");
  await expect(page.locator('textarea[name="store_cast_invitation[note]"]')).toBeVisible();
  await capture(page, "invitations", "01_cast_invitation_index.png");
  await page
    .locator('textarea[name="store_cast_invitation[note]"]')
    .fill(`manual store_admin capture cast invitation ${RUN_SLUG}`);
  await capture(page, "invitations", "02_cast_invitation_filled.png");
  await submitAndSettle(page, 'form[action="/admin/cast_invitations"] input[type="submit"]');
  await expect(page.locator("body")).toContainText("招待を発行しました");
  await capture(page, "invitations", "03_cast_invitation_issued.png");

  await gotoAndSettle(page, "/admin/store_admin_invitations");
  await expect(page).toHaveURL(/\/admin\/store_admin_invitations/);
  await capture(page, "invitations", "04_store_admin_invitation_index.png");
  await submitAndSettle(
    page,
    'form[action="/admin/store_admin_invitations"] input[type="submit"], form[action="/admin/store_admin_invitations"] button[type="submit"]'
  );
  await expect(page.locator("body")).toContainText("招待を発行しました");
  await capture(page, "invitations", "05_store_admin_invitation_issued.png");

  await gotoAndSettle(page, "/admin/drink_items");
  await expect(page.locator('form[action="/admin/drink_items"]')).toBeVisible();
  await capture(page, "drink_items", "01_index.png");
  await page
    .locator('form[action="/admin/drink_items"] input[name="drink_item[name]"]')
    .fill(`マニュアル撮影用ドリンク ${RUN_SLUG}`);
  await page
    .locator('form[action="/admin/drink_items"] input[name="drink_item[price_points]"]')
    .fill("1234");
  await page
    .locator('form[action="/admin/drink_items"] input[name="drink_item[position]"]')
    .fill("99");
  await capture(page, "drink_items", "02_new_filled.png");
  await submitAndSettle(page, 'form[action="/admin/drink_items"] input[type="submit"]');
  await expect(page.locator("body")).toContainText(`マニュアル撮影用ドリンク ${RUN_SLUG}`);
  await capture(page, "drink_items", "03_after_create.png");

  await gotoAndSettle(page, "/admin/cast_metrics");
  await expect(page).toHaveURL(/\/admin\/cast_metrics/);
  await capture(page, "metrics", "01_index.png");
  await gotoAndSettle(page, "/admin/cast_metrics?all_casts=1");
  await expect(page.locator("body")).toContainText("配信者別数値一覧");
  await capture(page, "metrics", "02_all_casts.png");

  await gotoAndSettle(page, "/admin/comment_reports");
  await expect(page).toHaveURL(/\/admin\/comment_reports/);
  await expect(page.locator("body")).toContainText("通報");
  await capture(page, "comment_reports", "01_index.png");

  await gotoAndSettle(page, "/admin/payout_account/edit");
  await expect(page.locator('form[action="/admin/payout_account"]')).toBeVisible();
  await capture(page, "payout_account", "01_edit_form.png");
  await page.locator('input#account_kind_bank').check();
  await page.locator('input[name="store_payout_account[bank_code]"]').fill("0001");
  await page.locator('input[name="store_payout_account[branch_code]"]').fill("001");
  await page.locator('select[name="store_payout_account[account_type]"]').selectOption("ordinary");
  await page.locator('input[name="store_payout_account[account_number]"]').fill("1234567");
  await page.locator('input[name="store_payout_account[account_holder_kana]"]').fill("マニュアルサツエイヨウ");
  await capture(page, "payout_account", "02_edit_filled.png");
  await submitAndSettle(page, 'form[action="/admin/payout_account"] input[type="submit"]');
  await expect(page.locator("body")).toContainText("精算・振込設定を更新しました");
  await capture(page, "payout_account", "03_after_update.png");

  await gotoAndSettle(page, "/admin/settlements");
  await expect(page).toHaveURL(/\/admin\/settlements/);
  await expect(page.locator("body")).toContainText("精算");
  await capture(page, "settlements", "01_index.png");
});
