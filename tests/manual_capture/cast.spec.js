const path = require("node:path");
const { expect, test } = require("@playwright/test");
const { captureSelection } = require("./selection_helpers");

const BASE_URL =
  process.env.MANUAL_CAPTURE_BASE_URL ||
  process.env.PLAYWRIGHT_BASE_URL ||
  "http://127.0.0.1:3000";
const SCREENSHOT_ROOT = path.resolve(__dirname, "../../docs/user_manual/images/cast");
const PASSWORD = "ManualCapture123!";

test.describe.configure({ mode: "serial" });
test.setTimeout(180_000);

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

test("cast selection screenshots", async ({ page }) => {
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

  // Current selection screenshots do not create preparations or contact IVS.
  // Full media/drink screenshots require a real local Stage and remain separate.
  await captureSelection(page, "cast", SCREENSHOT_ROOT);
  expect(participantTokenRequests).toBe(0);
});
