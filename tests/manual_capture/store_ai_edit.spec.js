const { test, expect } = require("@playwright/test")
const fs = require("node:fs")
const path = require("node:path")

// Local accounts and real Rails saves; AI and external image responses are stubbed.
test.setTimeout(90_000)
test.beforeEach(async ({ baseURL }) => {
  expect(["localhost", "127.0.0.1"]).toContain(new URL(baseURL).hostname)
})
const fields = ["description", "area", "business_type", "address", "phone_number", "business_hours",
  "website_url", "x_url", "instagram_url", "tiktok_url", "youtube_url"]
const result = (values = {}) => ({
  status: "partial",
  fields: Object.fromEntries(fields.map((field) => [field, values[field] ?? null])),
  field_sources: { area: ["https://example.com/store"], business_hours: ["https://example.com/store"] },
  sources: [{ url: "https://example.com/store", title: "店舗公式サイト" }]
})
const input = (page, field) => page.locator(`[name="store[${field}]"]`)
const badge = (page, field) => input(page, field).locator("xpath=../..").locator(".store-ai-autofill__badge")
const save = (page) => page.locator(".store-edit__bottom-save")

async function openRegularEditor(page) {
  page.on("dialog", (dialog) => dialog.accept())
  await page.goto("/stores/new_registration")
  await page.getByLabel("店舗名（必須）", { exact: true }).fill("既存AI入力確認用店舗")
  await page.getByLabel("店舗管理者のメールアドレス").fill(`edit-ai-${Date.now()}-${Math.random().toString(36).slice(2)}@example.test`)
  await page.getByLabel("パスワード（必須）", { exact: true }).fill("SetupTest123!")
  await page.getByLabel("パスワード（確認・必須）").fill("SetupTest123!")
  await page.getByRole("button", { name: "登録して店舗設定へ進む" }).click()
  await expect(page).toHaveURL(/registration_setup\/edit$/, { timeout: 20_000 })
  const storeId = new URL(page.url()).pathname.match(/\/stores\/(\d+)\//)[1]
  const editPath = `/admin/stores/${storeId}/edit`
  // Abandoning the initial step uses exactly the same editor as proxy/admin routes.
  await page.goto(editPath)
  await expect(page.locator(".store-ai-autofill__badge")).toHaveCount(11)
  return { editPath, storeId }
}

for (const [name, viewport, withImage] of [
  ["desktop", { width: 1440, height: 1000 }, false],
  ["mobile", { width: 390, height: 844 }, true]
]) {
  test(`${name}: saved values, protected re-search and real failed save keep editing state`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport)
    const errors = []
    page.on("pageerror", (error) => errors.push(error.message))
    const { editPath, storeId } = await openRegularEditor(page)
    await input(page, "description").fill("保存済み概要")
    await input(page, "business_hours").fill("保存済み営業時間")
    await save(page).click()
    await expect(page).toHaveURL(/\/dashboard$/, { timeout: 20_000 })
    await page.goto(editPath)
    await expect(save(page)).toBeDisabled()
    await expect(input(page, "published")).toHaveValue("false")
    await expect(page.getByText("登録済みの項目をAIで入れ直したい場合は、空欄にしてから検索してください。", { exact: true })).toBeVisible()
    await expect(page.locator(".store-ai-autofill__badge:visible")).toHaveCount(0)
    await page.screenshot({ path: testInfo.outputPath(`${name}-before.png`), fullPage: true })

    let saves = 0, searches = 0, imageRequests = 0, release
    page.on("request", (request) => {
      if (new URL(request.url()).pathname === `/admin/stores/${storeId}` && request.method() !== "GET") saves++
    })
    let next = result({ area: "AIの地域", business_hours: "上書き不可" })
    const first = new Promise((resolve) => { release = resolve })
    await page.route("**/admin/stores/*/ai_autofill", async (route) => {
      searches++
      if (searches === 1) await first
      await route.fulfill({ json: { ...next, image_token: withImage ? "signed" : null } })
    })
    await page.route("**/ai_autofill/image", async (route) => {
      imageRequests++
      await route.fulfill({ contentType: "image/jpeg",
        body: fs.readFileSync(path.resolve(__dirname, "../../test/fixtures/files/sample.jpg")),
        headers: { "X-Image-Source-Url": "https://example.com/image-source" } })
    })
    await input(page, "name").press("Enter")
    expect(saves).toBe(0)
    await page.getByRole("button", { name: "AIで店舗情報を自動入力", exact: true }).click()
    await expect(page.locator('[data-store-ai-autofill-target="content"]')).toHaveAttribute("inert", "")
    await expect(page.locator("header#app_header")).toHaveAttribute("inert", "")
    await expect(page.locator('.store-edit__action-bar').locator("xpath=..")).toHaveAttribute("inert", "")
    release()
    await expect(input(page, "area")).toHaveValue("AIの地域")
    await expect(page.locator('[data-store-ai-autofill-target="loading"]')).toBeHidden()
    await expect(input(page, "description")).toHaveValue("保存済み概要")
    await expect(input(page, "business_hours")).toHaveValue("保存済み営業時間")
    await expect(badge(page, "business_hours")).toBeHidden()
    await expect(badge(page, "phone_number")).toHaveText(/未/)
    await expect(save(page)).toBeEnabled()
    const preview = page.locator('[data-image-attachment-editor-target="currentPreview"]')
    const previewUrl = withImage ? await preview.getAttribute("src") : null

    await input(page, "area").fill("利用者が確認した地域")
    await input(page, "business_hours").fill("")
    next = result({ area: "上書き不可", business_hours: "19:00〜24:00" })
    await page.getByRole("button", { name: "AIで再検索", exact: true }).click()
    await expect(input(page, "business_hours")).toHaveValue("19:00〜24:00")
    await expect(input(page, "area")).toHaveValue("利用者が確認した地域")
    await expect(badge(page, "area")).toBeHidden()
    await expect(badge(page, "business_hours")).toHaveText(/AI/)
    await expect(page.locator(".modal.show")).toHaveCount(0)
    await expect(page.locator('[data-store-ai-autofill-target="loading"]')).toBeHidden()
    expect(imageRequests).toBe(withImage ? 1 : 0)
    expect(saves).toBe(0)

    await input(page, "area").fill("長".repeat(51))
    await save(page).click()
    await expect(page.locator('[data-image-pair-form-target="error"]')).toBeVisible()
    await expect(page).toHaveURL(new RegExp(`${editPath}$`))
    await expect(input(page, "area")).toHaveValue("長".repeat(51))
    await expect(badge(page, "business_hours")).toHaveText(/AI/)
    await expect(badge(page, "area")).toBeHidden()
    await expect(page.getByText("AIが参照した情報", { exact: true })).toBeVisible()
    if (withImage) {
      await expect(preview).toHaveAttribute("src", previewUrl)
      await expect(page.locator('[data-image-attachment-editor-target="operationInput"]')).toHaveValue("replace")
    }
    expect(searches).toBe(2)
    await input(page, "area").fill("確認済みの地域")
    await page.evaluate(() => window.scrollTo(0, 0))
    await page.screenshot({ path: testInfo.outputPath(`${name}-review.png`), fullPage: true })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await save(page).click()
    await expect(page).toHaveURL(/\/dashboard$/, { timeout: 20_000 })
    expect(saves).toBe(2)
    await page.goto(editPath)
    await expect(input(page, "business_hours")).toHaveValue("19:00〜24:00")
    await expect(input(page, "published")).toHaveValue("false")
    await expect(page.locator(".store-ai-autofill__badge:visible")).toHaveCount(0)
    await expect(save(page)).toBeDisabled()
    if (withImage) {
      await expect(preview).toBeVisible()
      await page.getByRole("button", { name: "AIで店舗情報を自動入力", exact: true }).click()
      await expect(page.locator('[data-store-ai-autofill-target="loading"]')).toBeHidden()
      expect(imageRequests).toBe(1)
      await expect(save(page)).toBeDisabled()
    }
    expect(errors).toEqual([])
  })
}

test("no text change stays clean; image-only changes can be saved and cancelled images are protected", async ({ page }) => {
  const { editPath } = await openRegularEditor(page)
  await input(page, "area").fill("保存済み地域")
  await save(page).click()
  await expect(page).toHaveURL(/\/dashboard$/, { timeout: 20_000 })
  await page.goto(editPath)
  let imageToken = null, images = 0
  await page.route("**/admin/stores/*/ai_autofill", (route) => route.fulfill({
    json: { ...result({ area: "上書き不可" }), image_token: imageToken }
  }))
  await page.route("**/ai_autofill/image", async (route) => {
    images++
    await route.fulfill({ contentType: "image/jpeg", body: fs.readFileSync(path.resolve(__dirname, "../../test/fixtures/files/sample.jpg")) })
  })
  await page.getByRole("button", { name: "AIで店舗情報を自動入力", exact: true }).click()
  await expect(page.getByText("入力内容に変更はありませんでした。必要に応じて手入力で修正できます。", { exact: true })).toBeVisible()
  await expect(save(page)).toBeDisabled()
  imageToken = "signed"
  await page.getByRole("button", { name: "AIで再検索", exact: true }).click()
  await expect(page.getByText("店舗画像を入力しました。内容を確認し、必要に応じて修正してください。", { exact: true })).toBeVisible()
  await expect(save(page)).toBeEnabled()
  await page.locator('[data-image-attachment-editor-target="imageMenuButton"]').click()
  await page.getByRole("button", { name: "画像の変更を取り消す", exact: true }).click()
  await expect(page.locator('[data-image-attachment-editor-target="operationInput"]')).toHaveValue("")
  await expect(save(page)).toBeDisabled()
  await page.getByRole("button", { name: "AIで再検索", exact: true }).click()
  await expect(page.locator('[data-store-ai-autofill-target="loading"]')).toBeHidden()
  expect(images).toBe(1)
})

test("save cancellation and permission failures preserve the live form and release controls", async ({ page }) => {
  const { storeId } = await openRegularEditor(page)
  await page.route("**/admin/stores/*/ai_autofill", (route) => route.fulfill({ json: result({ area: "保持するAI地域" }) }))
  await page.getByRole("button", { name: "AIで店舗情報を自動入力", exact: true }).click()
  await expect(input(page, "area")).toHaveValue("保持するAI地域")
  await badge(page, "area").locator("summary").focus()
  await page.keyboard.press("Enter")
  await expect(badge(page, "area").locator("p")).toBeVisible()
  await page.keyboard.press("Enter")
  await expect(badge(page, "area").locator("p")).toBeHidden()
  let saves = 0
  await page.route(`**/admin/stores/${storeId}`, async (route) => {
    saves++
    await route.fulfill({ status: 403 })
  })
  page.removeAllListeners("dialog")
  page.on("dialog", (dialog) => dialog.dismiss())
  await save(page).click()
  await expect(save(page)).toBeEnabled()
  expect(saves).toBe(0)
  page.removeAllListeners("dialog")
  page.on("dialog", (dialog) => dialog.accept())
  await page.locator(".store-edit__save").click()
  await expect(page.locator('[data-image-pair-form-target="error"]')).toHaveText(/再ログインまたは権限の確認/)
  await expect(input(page, "area")).toHaveValue("保持するAI地域")
  await expect(badge(page, "area")).toHaveText(/AI/)
  await expect(page.locator('[data-store-ai-autofill-target="content"]')).not.toHaveAttribute("inert", "")
  await expect(page.locator(".store-edit__save")).toBeEnabled()
  expect(saves).toBe(1)
})
