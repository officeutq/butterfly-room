const fs = require("node:fs");
const path = require("node:path");
const { execFileSync, execSync } = require("node:child_process");
const { expect, test } = require("@playwright/test");

const BASE_URL =
  process.env.MANUAL_CAPTURE_BASE_URL ||
  process.env.PLAYWRIGHT_BASE_URL ||
  "http://127.0.0.1:3000";
const SCREENSHOT_ROOT = path.resolve(__dirname, "../../docs/user_manual/images/customer");
const PASSWORD = "ManualCapture123!";
const FULL_PAGE = process.env.MANUAL_CAPTURE_FULL_PAGE === "1";
const PREPARE_COMMAND = process.env.MANUAL_CAPTURE_CUSTOMER_PREPARE_COMMAND;
const SKIP_PREPARE = process.env.MANUAL_CAPTURE_SKIP_CUSTOMER_VIEWER_PREPARE === "1";

const sections = [
  "dashboard",
  "home",
  "stores",
  "users",
  "booths",
  "favorites",
  "profile",
  "phone",
  "wallet",
  "live",
];

test.describe.configure({ mode: "serial" });
test.setTimeout(180_000);

test.beforeAll(() => {
  for (const section of sections) {
    const dir = path.join(SCREENSHOT_ROOT, section);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
  }

  prepareCustomerViewerData();
});

function prepareCustomerViewerData() {
  if (SKIP_PREPARE) return;

  if (PREPARE_COMMAND) {
    execSync(PREPARE_COMMAND, {
      cwd: path.resolve(__dirname, "../.."),
      stdio: "inherit",
      shell: true,
    });
    return;
  }

  execFileSync(
    "docker",
    ["compose", "exec", "-T", "app", "bin/rails", "manual_capture:prepare_customer_viewer"],
    {
      cwd: path.resolve(__dirname, "../.."),
      stdio: "inherit",
    }
  );
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

async function submitAndWaitForURL(page, selector, urlMatcher) {
  await Promise.all([
    page.waitForURL(urlMatcher, { timeout: 20_000 }),
    page.locator(selector).first().click(),
  ]);
  await settle(page);
}

async function loginAsCustomer(page) {
  await gotoAndSettle(page, "/users/sign_in");
  await page.locator('input[name="user[email]"]').fill("manual+customer@example.test");
  await page.locator('input[name="user[password]"]').fill(PASSWORD);
  await submitAndWaitForURL(
    page,
    'form input[type="submit"], form button[type="submit"]',
    (url) => !url.pathname.includes("/users/sign_in")
  );
}

async function installExternalServiceFakes(page) {
  await page.route(/web-broadcast\.live-video\.net\/.*amazon-ivs-web-broadcast\.js/, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/javascript",
      body: `
        window.IVSBroadcastClient = {
          SubscribeType: { AUDIO_VIDEO: "AUDIO_VIDEO" },
          StageEvents: {
            STAGE_CONNECTION_STATE_CHANGED: "STAGE_CONNECTION_STATE_CHANGED",
            STAGE_PARTICIPANT_STREAMS_ADDED: "STAGE_PARTICIPANT_STREAMS_ADDED",
            STAGE_PARTICIPANT_STREAMS_REMOVED: "STAGE_PARTICIPANT_STREAMS_REMOVED"
          },
          Stage: class {
            constructor() {}
            on() {}
            async join() {}
            leave() {}
          }
        };
      `,
    });
  });

  await page.route(/\/stream_sessions\/\d+\/ivs_participant_tokens/, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        stream_session_id: "manual-capture",
        ivs_stage_arn: "arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local-secondary",
        role: "viewer",
        participant_token: "manual-capture-fake-token",
      }),
    });
  });
}

async function hideDevelopmentViewerLabels(page) {
  await page.addStyleTag({
    content: `
      .viewer-slot-label {
        display: none !important;
      }
    `,
  });
}

async function openBoothByName(page, boothName) {
  await gotoAndSettle(page, `/?mode=booths&q=${encodeURIComponent(boothName)}`);
  const card = page.locator(".booths-card", { hasText: boothName }).first();
  await expect(card).toBeVisible();
  await Promise.all([
    page.waitForURL(/\/booths\/\d+/, { timeout: 20_000 }),
    card.locator(".booths-card-name-button").first().click(),
  ]);
  await settle(page);
}

test("customer normal operation screenshots", async ({ page }) => {
  await installExternalServiceFakes(page);
  await loginAsCustomer(page);

  await gotoAndSettle(page, "/dashboard");
  await expect(page).toHaveURL(/\/dashboard/);
  await expect(page.locator("body")).toContainText("プロフィール編集");
  await expect(page.locator("body")).toContainText("電話番号認証");
  await capture(page, "dashboard", "01_dashboard.png");

  await gotoAndSettle(page, "/profile/edit");
  await expect(page.locator('input[name="user[display_name]"]')).toBeVisible();
  await capture(page, "profile", "01_edit_form.png");

  await page.locator('input[name="user[display_name]"]').fill("マニュアル撮影用 視聴者");
  await page
    .locator('textarea[name="user[bio]"]')
    .fill("マニュアル撮影用の customer（視聴者）通常操作撮影で使うプロフィールです。");
  await capture(page, "profile", "02_edit_filled.png");

  await submitAndWaitForURL(
    page,
    'form[action="/profile"] input[type="submit"], form[action="/profile"] button[type="submit"]',
    (url) => url.pathname === "/"
  );
  await expect(page.locator("body")).toContainText("プロフィールを更新しました");
  await capture(page, "profile", "03_after_update_home.png");

  await gotoAndSettle(page, "/phone_verification");
  await expect(page.locator("body")).toContainText("電話番号認証");
  await capture(page, "phone", "01_new_form.png");
  await page.locator('input[name="phone_number"]').fill("090-0000-0404");
  await capture(page, "phone", "02_new_filled.png");

  await gotoAndSettle(page, "/?mode=booths");
  await expect(page.locator("body")).toContainText("マニュアル撮影用ブース");
  await expect(page.locator("body")).toContainText("マニュアル撮影用サブブース");
  await capture(page, "home", "01_booths_index.png");

  await gotoAndSettle(page, "/?mode=booths&q=サブ");
  await expect(page.locator("body")).toContainText("マニュアル撮影用サブブース");
  await capture(page, "home", "02_booth_search.png");

  await gotoAndSettle(page, "/?mode=stores");
  await expect(page.locator("body")).toContainText("マニュアル撮影用店舗");
  await capture(page, "home", "03_stores_index.png");

  await gotoAndSettle(page, "/?mode=users");
  await expect(page.locator("body")).toContainText("マニュアル撮影用 キャスト");
  await capture(page, "home", "04_users_index.png");

  await gotoAndSettle(page, "/?mode=stores&q=マニュアル撮影用店舗");
  const storeLink = page.locator("a.stores-card-name-link", { hasText: "マニュアル撮影用店舗" }).first();
  await expect(storeLink).toBeVisible();
  await Promise.all([
    page.waitForURL(/\/stores\/\d+/, { timeout: 20_000 }),
    storeLink.click(),
  ]);
  await settle(page);
  await expect(page.locator("body")).toContainText("マニュアル撮影用店舗");
  await expect(page.locator("body")).toContainText("マニュアル撮影用ブース");
  await capture(page, "stores", "01_show.png");

  await gotoAndSettle(page, "/?mode=users&q=キャスト");
  const userLink = page.locator("a.users-card-name-link", { hasText: "マニュアル撮影用 キャスト" }).first();
  await expect(userLink).toBeVisible();
  await Promise.all([
    page.waitForURL(/\/users\/\d+/, { timeout: 20_000 }),
    userLink.click(),
  ]);
  await settle(page);
  await expect(page.locator("body")).toContainText("マニュアル撮影用 キャスト");
  await capture(page, "users", "01_cast_show.png");

  await openBoothByName(page, "マニュアル撮影用ブース");
  await expect(page.locator("body")).toContainText("マニュアル撮影用ブース");
  await capture(page, "booths", "01_offline_show.png");

  await openBoothByName(page, "マニュアル撮影用サブブース");
  await expect(page.locator("body")).toContainText("マニュアル撮影用ライブ配信");
  await expect(page.locator('input[name="comment[body]"]')).toBeVisible();
  await hideDevelopmentViewerLabels(page);
  await page.waitForTimeout(1_000);
  await capture(page, "live", "01_live_viewer.png");

  await page.locator('input[name="comment[body]"]').fill("コメント入力例です");
  await capture(page, "live", "02_comment_filled.png");

  await page.locator('button[aria-label="ドリンクメニューを開く"]').first().click();
  await expect(page.locator("#viewer_drink_menu .viewer-drink-menu-list")).toBeVisible();
  await capture(page, "live", "03_drink_menu.png");

  await page.keyboard.press("Escape");
  await expect(page.locator("#viewer_drink_menu_panel")).toHaveClass(/d-none/);

  await page.locator("#wallet_balance").click();
  await expect(page.locator("#modal")).toContainText("ポイント購入");
  await capture(page, "wallet", "01_purchase_modal.png");

  await gotoAndSettle(page, "/favorites/booths");
  await expect(page.locator("body")).toContainText("マニュアル撮影用サブブース");
  await capture(page, "favorites", "01_booths_index.png");

  await gotoAndSettle(page, "/favorites/stores");
  await expect(page.locator("body")).toContainText("マニュアル撮影用店舗");
  await capture(page, "favorites", "02_stores_index.png");

  await gotoAndSettle(page, "/favorites/users");
  await expect(page.locator("body")).toContainText("マニュアル撮影用 キャスト");
  await capture(page, "favorites", "03_users_index.png");
});
