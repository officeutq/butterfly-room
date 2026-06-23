const fs = require("node:fs");
const path = require("node:path");
const { expect, test } = require("@playwright/test");

const BASE_URL =
  process.env.MANUAL_CAPTURE_BASE_URL ||
  process.env.PLAYWRIGHT_BASE_URL ||
  "http://127.0.0.1:3000";
const SCREENSHOT_ROOT = path.resolve(__dirname, "../../docs/user_manual/images/cast");
const PASSWORD = "ManualCapture123!";
const FULL_PAGE = process.env.MANUAL_CAPTURE_FULL_PAGE !== "0";

const sections = [
  "dashboard",
  "booths",
  "booth_edit",
  "live",
  "stream_sessions",
  "drink_orders",
];

test.describe.configure({ mode: "serial" });
test.setTimeout(180_000);
test.use({
  permissions: ["camera", "microphone"],
  launchOptions: {
    args: [
      "--use-fake-device-for-media-stream",
      "--use-fake-ui-for-media-stream",
    ],
  },
});

test.beforeAll(() => {
  for (const section of sections) {
    const dir = path.join(SCREENSHOT_ROOT, section);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
  }
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

async function submitAndWaitForURL(page, selector, urlMatcher) {
  await Promise.all([
    page.waitForURL(urlMatcher, { timeout: 20_000 }),
    page.locator(selector).first().click(),
  ]);
  await settle(page);
}

async function loginAsCast(page) {
  await gotoAndSettle(page, "/users/sign_in");
  await page.locator('input[name="user[email]"]').fill("manual+cast@example.test");
  await page.locator('input[name="user[password]"]').fill(PASSWORD);
  await submitAndWaitForURL(
    page,
    'form input[type="submit"], form button[type="submit"]',
    (url) => !url.pathname.includes("/users/sign_in")
  );
}

async function primaryBoothFromIndex(page) {
  const primaryCard = page
    .locator(".cast-booths-card", { hasText: "マニュアル撮影用ブース" })
    .first();

  await expect(primaryCard).toBeVisible();

  const editHref = await primaryCard
    .locator('a:has-text("このブースを選択して編集")')
    .first()
    .getAttribute("href");
  const enterHref = await primaryCard
    .locator('a:has-text("配信")')
    .first()
    .getAttribute("href");
  const match = editHref && editHref.match(/\/cast\/booths\/(\d+)\/edit/);

  if (!match || !enterHref) {
    throw new Error("primary manual booth links were not found");
  }

  return {
    id: match[1],
    showPath: `/cast/booths/${match[1]}`,
    editPath: editHref,
    enterPath: enterHref,
  };
}

function streamSessionIdFromTokenUrl(tokenUrl) {
  const match = tokenUrl && tokenUrl.match(/\/stream_sessions\/(\d+)\/ivs_participant_tokens/);
  if (!match) throw new Error("stream session token URL was not found");

  return match[1];
}

test("cast normal operation screenshots", async ({ page }) => {
  let participantTokenRequests = 0;
  await page.route(/\/stream_sessions\/\d+\/ivs_participant_tokens/, async (route) => {
    participantTokenRequests += 1;
    await route.fulfill({
      status: 503,
      contentType: "application/json",
      body: JSON.stringify({ error: "blocked_for_manual_capture" }),
    });
  });

  await loginAsCast(page);

  await gotoAndSettle(page, "/dashboard");
  await expect(page).toHaveURL(/\/dashboard/);
  await expect(page.locator("body")).toContainText("ブース情報");
  await expect(page.locator("body")).toContainText("ブース編集");
  await expect(page.locator("body")).toContainText("配信履歴");
  await capture(page, "dashboard", "01_dashboard.png");

  await gotoAndSettle(page, "/cast/booths");
  await expect(page).toHaveURL(/\/cast\/booths/);
  await expect(page.locator("body")).toContainText("マニュアル撮影用ブース");
  await expect(page.locator("body")).toContainText("マニュアル撮影用サブブース");
  await capture(page, "booths", "01_index.png");

  const primaryBooth = await primaryBoothFromIndex(page);

  await gotoAndSettle(page, primaryBooth.showPath);
  await expect(page).toHaveURL(new RegExp(`/cast/booths/${primaryBooth.id}$`));
  await expect(page.locator("body")).toContainText("ブース情報");
  await capture(page, "booths", "02_show.png");

  await gotoAndSettle(page, primaryBooth.editPath);
  await expect(page.locator('input[name="booth[name]"]')).toBeVisible();
  await capture(page, "booth_edit", "01_edit_form.png");

  await page.locator('input[name="booth[name]"]').fill("マニュアル撮影用ブース");
  await page
    .locator('textarea[name="booth[description]"]')
    .fill("マニュアル撮影用の cast（配信者）通常操作撮影で確認するブース説明です。");
  await capture(page, "booth_edit", "02_edit_filled.png");

  await submitAndWaitForURL(
    page,
    'form[action*="/cast/booths/"] input[type="submit"], form[action*="/cast/booths/"] button[type="submit"]',
    /\/dashboard/
  );
  await expect(page.locator("body")).toContainText("ブースを更新しました");
  await capture(page, "booth_edit", "03_after_update_dashboard.png");

  await gotoAndSettle(page, "/cast/booths");
  await expect(page.locator("body")).toContainText("選択中");
  await capture(page, "booths", "03_index_current_booth.png");

  await gotoAndSettle(page, `/cast/booths/${primaryBooth.id}/stream_sessions`);
  await expect(page).toHaveURL(new RegExp(`/cast/booths/${primaryBooth.id}/stream_sessions`));
  await expect(page.locator("body")).toContainText("配信履歴");
  await capture(page, "stream_sessions", "01_index_empty.png");

  await gotoAndSettle(page, primaryBooth.enterPath);
  await expect(page).toHaveURL(new RegExp(`/cast/booths/${primaryBooth.id}/live`));
  await expect(page.locator("body")).toContainText("配信開始");
  await expect(page.locator("body")).toContainText("配信タイトル");
  await page.waitForTimeout(1_000);
  await capture(page, "live", "01_live_standby_initial.png");

  expect(participantTokenRequests).toBe(0);

  const tokenUrl = await page
    .locator(".cast-live-screen")
    .first()
    .getAttribute("data-ivs-publisher-token-url-value");
  const streamSessionId = streamSessionIdFromTokenUrl(tokenUrl);

  await gotoAndSettle(page, `/cast/stream_sessions/${streamSessionId}/pending_drink_orders`);
  await expect(page.locator("body")).toContainText("未消化のドリンクはありません");
  await capture(page, "drink_orders", "01_pending_empty.png");
});
