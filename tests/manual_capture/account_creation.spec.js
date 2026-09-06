const fs = require("node:fs");
const path = require("node:path");
const { expect, test } = require("@playwright/test");

const BASE_URL =
  process.env.MANUAL_CAPTURE_BASE_URL ||
  process.env.PLAYWRIGHT_BASE_URL ||
  "http://127.0.0.1:3000";
const SCREENSHOT_ROOT = path.resolve(__dirname, "../../docs/user_manual/images/account_creation");
const PASSWORD = "ManualCapture123!";
const RUN_ID =
  process.env.MANUAL_CAPTURE_RUN_ID ||
  new Date().toISOString().replace(/\D/g, "").slice(0, 14);
const RUN_SLUG = RUN_ID.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 24) || "local";
const FULL_PAGE = process.env.MANUAL_CAPTURE_FULL_PAGE === "1";

const sections = [
  "customer",
  "store_admin_registration",
  "cast_invitation",
  "store_admin_invitation",
];

const accounts = {
  customer: `manual+account_flow_customer_${RUN_SLUG}@example.test`,
  storeAdminRegistration: `manual+account_flow_store_admin_registration_${RUN_SLUG}@example.test`,
  castInvitation: `manual+account_flow_cast_invitation_${RUN_SLUG}@example.test`,
  storeAdminInvitation: `manual+account_flow_store_admin_invitation_${RUN_SLUG}@example.test`,
};

test.describe.configure({ mode: "serial" });
test.setTimeout(60_000);

test.beforeAll(() => {
  for (const section of sections) {
    const dir = path.join(SCREENSHOT_ROOT, section);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
  }

  console.log(`manual account creation run id: ${RUN_ID}`);
  console.log(`customer: ${accounts.customer}`);
  console.log(`store_admin_registration: ${accounts.storeAdminRegistration}`);
  console.log(`cast_invitation: ${accounts.castInvitation}`);
  console.log(`store_admin_invitation: ${accounts.storeAdminInvitation}`);
});

function appUrl(pathOrUrl) {
  if (/^https?:\/\//.test(pathOrUrl)) return pathOrUrl;

  return new URL(pathOrUrl, BASE_URL).toString();
}

function localizeIssuedUrl(issuedUrl) {
  const issued = new URL(issuedUrl);
  const localBase = new URL(BASE_URL);
  issued.protocol = localBase.protocol;
  issued.host = localBase.host;
  return issued.toString();
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

async function submitFirstFormAndWait(page, urlMatcher) {
  await Promise.all([
    page.waitForURL(urlMatcher, { timeout: 15_000 }),
    page.locator('form input[type="submit"], form button[type="submit"]').first().click(),
  ]);
  await settle(page);
}

async function submitSelectorAndWait(page, selector, urlMatcher) {
  await Promise.all([
    page.waitForURL(urlMatcher, { timeout: 15_000 }),
    page.locator(selector).first().click(),
  ]);
  await settle(page);
}

async function submitSamePage(page, selector) {
  await page.locator(selector).first().click();
  await settle(page);
}

async function loginAsStoreAdmin(page) {
  await gotoAndSettle(page, "/users/sign_in");
  await page.locator('input[name="user[email]"]').fill("manual+store_admin@example.test");
  await page.locator('input[name="user[password]"]').fill(PASSWORD);
  await submitFirstFormAndWait(page, (url) => !url.pathname.includes("/users/sign_in"));
}

async function latestInvitationUrl(page) {
  const code = page.locator("code.referral-code-url-inline").first();
  await expect(code).toBeVisible();
  return localizeIssuedUrl((await code.innerText()).trim());
}

async function acceptInvitationAndWait(page, urlMatcher) {
  page.once("dialog", async (dialog) => {
    await dialog.accept();
  });

  await submitSelectorAndWait(
    page,
    'form[action$="/accept"] input[type="submit"], form[action$="/accept"] button[type="submit"]',
    urlMatcher
  );
}

test("customer self registration", async ({ page }) => {
  await gotoAndSettle(page, "/sign_up");
  await expect(page.locator('input[name="customer_registration[email]"]')).toBeVisible();
  await capture(page, "customer", "01_signup_form.png");

  await page.locator('input[name="customer_registration[email]"]').fill(accounts.customer);
  await page.locator('input[name="customer_registration[password]"]').fill(PASSWORD);
  await page.locator('input[name="customer_registration[password_confirmation]"]').fill(PASSWORD);
  await capture(page, "customer", "02_signup_filled.png");

  await submitFirstFormAndWait(page, /\/profile\/edit/);
  await expect(page.locator('input[name="user[display_name]"]')).toBeVisible();
  await capture(page, "customer", "03_after_signup_profile_edit.png");
});

test("store admin store registration", async ({ page }) => {
  await gotoAndSettle(page, "/stores/new_registration?ref=MANUAL-CAPTURE-LOCAL");
  await expect(page.locator('input[name="store_registration[store_name]"]')).toBeVisible();
  await capture(page, "store_admin_registration", "01_registration_form.png");

  await page
    .locator('input[name="store_registration[store_name]"]')
    .fill(`マニュアル撮影用アカウント作成 店舗 ${RUN_SLUG}`);
  await page.locator('input[name="store_registration[email]"]').fill(accounts.storeAdminRegistration);
  await page.locator('input[name="store_registration[password]"]').fill(PASSWORD);
  await page.locator('input[name="store_registration[password_confirmation]"]').fill(PASSWORD);
  await page.locator('input[name="store_registration[referral_code]"]').fill("MANUAL-CAPTURE-LOCAL");
  await capture(page, "store_admin_registration", "02_registration_filled.png");

  await submitFirstFormAndWait(page, /\/admin\/stores\/\d+\/registration_setup\/edit/);
  await expect(page.locator('input[name="store[name]"]')).toBeVisible();
  await capture(page, "store_admin_registration", "03_after_registration_initial_setup.png");

  await submitFirstFormAndWait(page, /\/stores\/registration\/thanks/);
  await expect(page.getByRole("heading", { name: "店舗情報の登録・公開が完了しました" })).toBeVisible();
  await capture(page, "store_admin_registration", "04_after_initial_setup_thanks.png");

  await page.getByRole("link", { name: "ダッシュボードへ進む" }).click();
  await page.waitForURL(/\/dashboard/);
  await capture(page, "store_admin_registration", "05_after_registration_dashboard.png");
});

test("cast invitation registration", async ({ page, browser }) => {
  await loginAsStoreAdmin(page);
  await gotoAndSettle(page, "/admin/cast_invitations");
  await expect(page.locator('textarea[name="store_cast_invitation[note]"]')).toBeVisible();
  await capture(page, "cast_invitation", "01_admin_invitation_form.png");

  await page
    .locator('textarea[name="store_cast_invitation[note]"]')
    .fill(`manual-account-flow cast ${RUN_SLUG}`);
  await capture(page, "cast_invitation", "02_admin_invitation_filled.png");

  await submitSamePage(page, 'form[action="/admin/cast_invitations"] input[type="submit"]');
  const invitationUrl = await latestInvitationUrl(page);
  await capture(page, "cast_invitation", "03_admin_invitation_issued.png");

  const guestContext = await browser.newContext();
  const guestPage = await guestContext.newPage();
  try {
    await gotoAndSettle(guestPage, invitationUrl);
    await expect(guestPage.locator('a[href*="/cast/sign_up"]')).toBeVisible();
    await capture(guestPage, "cast_invitation", "04_invitation_guest.png");

    await Promise.all([
      guestPage.waitForURL(/\/cast\/sign_up\?token=/, { timeout: 15_000 }),
      guestPage.locator('a[href*="/cast/sign_up"]').first().click(),
    ]);
    await settle(guestPage);
    await expect(guestPage.locator('input[name="cast_registration[email]"]')).toBeVisible();
    await capture(guestPage, "cast_invitation", "05_signup_form.png");

    await guestPage.locator('input[name="cast_registration[email]"]').fill(accounts.castInvitation);
    await guestPage.locator('input[name="cast_registration[password]"]').fill(PASSWORD);
    await guestPage.locator('input[name="cast_registration[password_confirmation]"]').fill(PASSWORD);
    await capture(guestPage, "cast_invitation", "06_signup_filled.png");

    await submitFirstFormAndWait(guestPage, /\/cast_invitations\//);
    await capture(guestPage, "cast_invitation", "07_after_signup_invitation.png");

    await acceptInvitationAndWait(guestPage, /\/profile\/edit/);
    await expect(guestPage.locator('input[name="user[display_name]"]')).toBeVisible();
    await capture(guestPage, "cast_invitation", "08_after_accept_profile_edit.png");

    await guestPage.locator('input[name="user[display_name]"]').fill(`マニュアル撮影用 キャスト招待 ${RUN_SLUG}`);
    await guestPage.locator('textarea[name="user[bio]"]').fill("アカウント作成フロー撮影用の自己紹介です。");
    await capture(guestPage, "cast_invitation", "09_profile_filled.png");

    await submitSelectorAndWait(
      guestPage,
      'form[action="/profile"] input[type="submit"], form[action="/profile"] button[type="submit"]',
      /\/cast\/booths\/\d+\/edit/
    );
    await expect(guestPage.locator('input[name="booth[name]"]')).toBeVisible();
    await capture(guestPage, "cast_invitation", "10_after_profile_booth_edit.png");

    await guestPage.locator('input[name="booth[name]"]').fill(`マニュアル撮影用 招待キャストブース ${RUN_SLUG}`);
    await guestPage.locator('textarea[name="booth[description]"]').fill("アカウント作成フロー撮影用のブース説明です。");
    await capture(guestPage, "cast_invitation", "11_booth_filled.png");

    await submitSelectorAndWait(
      guestPage,
      'form[action*="/cast/booths/"] input[type="submit"], form[action*="/cast/booths/"] button[type="submit"]',
      (url) => url.pathname === "/"
    );
    await capture(guestPage, "cast_invitation", "12_after_booth_update_home.png");
  } finally {
    await guestContext.close();
  }
});

test("additional store admin invitation registration", async ({ page, browser }) => {
  await loginAsStoreAdmin(page);
  await gotoAndSettle(page, "/admin/store_admin_invitations");
  await capture(page, "store_admin_invitation", "01_admin_invitation_form.png");

  await submitSamePage(page, 'form[action="/admin/store_admin_invitations"] input[type="submit"], form[action="/admin/store_admin_invitations"] button[type="submit"]');
  const invitationUrl = await latestInvitationUrl(page);
  await capture(page, "store_admin_invitation", "02_admin_invitation_issued.png");

  const guestContext = await browser.newContext();
  const guestPage = await guestContext.newPage();
  try {
    await gotoAndSettle(guestPage, invitationUrl);
    await expect(guestPage.locator('a[href*="/store_admin/sign_up"]')).toBeVisible();
    await capture(guestPage, "store_admin_invitation", "03_invitation_guest.png");

    await Promise.all([
      guestPage.waitForURL(/\/store_admin\/sign_up\?token=/, { timeout: 15_000 }),
      guestPage.locator('a[href*="/store_admin/sign_up"]').first().click(),
    ]);
    await settle(guestPage);
    await expect(guestPage.locator('input[name="store_admin_registration[email]"]')).toBeVisible();
    await capture(guestPage, "store_admin_invitation", "04_signup_form.png");

    await guestPage.locator('input[name="store_admin_registration[email]"]').fill(accounts.storeAdminInvitation);
    await guestPage.locator('input[name="store_admin_registration[password]"]').fill(PASSWORD);
    await guestPage.locator('input[name="store_admin_registration[password_confirmation]"]').fill(PASSWORD);
    await capture(guestPage, "store_admin_invitation", "05_signup_filled.png");

    await submitFirstFormAndWait(guestPage, /\/store_admin_invitations\//);
    await capture(guestPage, "store_admin_invitation", "06_after_signup_invitation.png");

    await acceptInvitationAndWait(guestPage, /\/dashboard/);
    await capture(guestPage, "store_admin_invitation", "07_after_accept_dashboard.png");
  } finally {
    await guestContext.close();
  }
});
