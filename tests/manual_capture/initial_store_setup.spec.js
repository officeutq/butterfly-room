const { test, expect } = require("@playwright/test")
const path = require("node:path")

// Run against a local Rails app. AI responses are intercepted; no paid AI calls
// are made. Each run creates its own local store-admin account and store.
test.setTimeout(90_000)
const fields = ["description", "area", "business_type", "address", "phone_number", "business_hours",
  "website_url", "x_url", "instagram_url", "tiktok_url", "youtube_url"]
const result = (values) => ({
  status: "partial",
  fields: Object.fromEntries(fields.map((field) => [field, values[field] ?? null])),
  field_sources: { area: ["https://example.com/store"], description: ["https://example.com/store"] },
  sources: [{ url: "https://example.com/store", title: "店舗公式サイト" }]
})

async function register(page, testInfo) {
  await page.goto("/stores/new_registration")
  if (testInfo) await page.screenshot({ path: testInfo.outputPath("registration.png"), fullPage: true })
  await page.getByLabel("店舗名（必須）", { exact: true }).fill("AI入力確認用店舗")
  await page.getByLabel("店舗管理者のメールアドレス").fill(`setup-${Date.now()}-${Math.random().toString(36).slice(2)}@example.test`)
  await page.getByLabel("パスワード（必須）", { exact: true }).fill("SetupTest123!")
  await page.getByLabel("パスワード（確認・必須）").fill("SetupTest123!")
  await page.getByRole("button", { name: "登録して店舗設定へ進む" }).click()
  await expect(page).toHaveURL(/registration_setup\/edit$/, { timeout: 20_000 })
  await expect(page.locator(".store-ai-autofill__badge")).toHaveCount(11)
}

function badge(page, field) {
  return page.locator(`[name="store[${field}]"]`).locator("xpath=../..").locator(".store-ai-autofill__badge")
}

for (const [name, viewport, withImage] of [
  ["desktop", { width: 1440, height: 1000 }, false],
  ["mobile", { width: 390, height: 844 }, true]
]) {
  test(`${name}: AI badges, protected re-search and failed save through publication`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport)
    const errors = []
    page.on("pageerror", (error) => errors.push(error.message))
    let searches = 0
    let saves = 0
    let release
    let nextResult = result({ area: "渋谷", description: "AIで入力した紹介文" })
    const firstSearch = new Promise((resolve) => { release = resolve })
    await page.route("**/admin/stores/*/ai_autofill", async (route) => {
      searches++
      expect(route.request().postDataJSON()).toEqual({ store_ai_autofill: { store_name: "確認済み店舗" } })
      if (searches === 1) await firstSearch
      await route.fulfill({ json: nextResult })
    })
    page.on("request", (request) => {
      if (request.url().endsWith("/registration_setup") && request.method() !== "GET") saves++
    })
    await register(page, testInfo)
    const storeId = new URL(page.url()).pathname.match(/\/stores\/(\d+)\//)[1]
    const storeName = page.getByLabel("店舗名（必須）", { exact: true })
    const publish = page.getByRole("button", { name: "店舗情報を保存して公開する", exact: true })
    await expect(storeName).toHaveValue("AI入力確認用店舗")
    await expect(publish).toBeHidden()
    await expect(page.getByRole("button", { name: "自分で入力する" })).toHaveCount(0)
    await page.screenshot({ path: testInfo.outputPath(`${name}-initial.png`), fullPage: true })
    await storeName.press("Enter")
    expect(saves).toBe(0)
    await storeName.fill("")
    await page.getByRole("button", { name: "AIで店舗情報を自動入力", exact: true }).click()
    await expect(page.getByText("店舗名を入力してください", { exact: true })).toBeVisible()
    expect(searches).toBe(0)
    await storeName.fill("確認済み店舗")
    await page.getByRole("button", { name: "AIで店舗情報を自動入力", exact: true }).click()
    await expect(page.locator('[data-store-ai-autofill-target="loading"]')).toBeVisible()
    await expect(page.locator('[data-store-ai-autofill-target="content"]')).toHaveAttribute("inert", "")
    await expect(page.getByRole("banner", { includeHidden: true })).toHaveAttribute("inert", "")
    release()
    await expect(page.getByRole("heading", { name: "店舗情報を確認しましょう" })).toBeVisible()
    await expect(badge(page, "area")).toHaveText(/AI/)
    await expect(badge(page, "business_hours")).toHaveText(/未/)
    await badge(page, "business_hours").locator("summary").click()
    await expect(badge(page, "business_hours").locator("p")).toBeVisible()
    await badge(page, "business_hours").locator("summary").click()
    await page.getByLabel("地域", { exact: true }).fill("手入力の地域")
    await expect(badge(page, "area")).toBeHidden()
    nextResult = result({ area: "上書きされない地域", phone_number: "03-1234-5678" })
    await page.getByRole("button", { name: "AIで再検索", exact: true }).click()
    await expect(page.getByLabel("電話番号", { exact: true })).toHaveValue("03-1234-5678")
    await expect(page.getByLabel("地域", { exact: true })).toHaveValue("手入力の地域")
    await expect(page.getByLabel("概要", { exact: true })).toHaveValue("")
    await expect(badge(page, "description")).toHaveText(/未/)
    await expect(storeName).toHaveValue("確認済み店舗")
    expect(searches).toBe(2)
    expect(saves).toBe(0)
    await expect(page.locator(".modal.show")).toHaveCount(0)

    if (withImage) {
      await page.locator('input[data-image-attachment-editor-target="fileInput"]').setInputFiles(path.resolve(__dirname, "../../test/fixtures/files/sample.jpg"))
      const apply = page.locator('[data-image-attachment-editor-target~="applyButton"]')
      await expect(apply).toBeEnabled()
      await apply.click()
      await expect(page.locator('[data-image-attachment-editor-target="operationInput"]')).toHaveValue("replace")
    }

    // Server-side validation exercises the real save path with and without an image.
    await page.getByLabel("地域", { exact: true }).fill("長".repeat(51))
    await publish.click()
    await expect(page.locator('[data-image-pair-form-target="error"]')).toBeVisible()
    await expect(page.getByRole("heading", { name: "店舗情報を確認しましょう" })).toBeVisible()
    await expect(page.getByLabel("地域", { exact: true })).toHaveValue("長".repeat(51))
    await expect(badge(page, "phone_number")).toHaveText(/AI/)
    await expect(badge(page, "area")).toBeHidden()
    await expect(page.getByText("AIが参照した情報", { exact: true })).toBeVisible()
    expect(searches).toBe(2)
    await page.getByLabel("地域", { exact: true }).fill("公開確認用")
    await page.screenshot({ path: testInfo.outputPath(`${name}-review.png`), fullPage: true })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    await publish.click()
    await expect(page).toHaveURL(/\/stores\/registration\/thanks$/)
    await expect(page.getByRole("heading", { name: "店舗情報の登録・公開が完了しました" })).toBeVisible()
    await page.screenshot({ path: testInfo.outputPath(`${name}-thanks.png`), fullPage: true })
    await page.getByRole("link", { name: "店舗ページを見る", exact: true }).click()
    await expect(page).toHaveURL(new RegExp(`/stores/${storeId}$`))
    await expect(page.getByRole("heading", { name: "確認済み店舗", exact: true })).toBeVisible()
    expect(saves).toBe(2)
    expect(searches).toBe(2)
    expect(errors).toEqual([])
  })
}

test("AI unavailability allows manual publishing without badges or an automatic retry", async ({ page }) => {
  let searches = 0
  await page.route("**/admin/stores/*/ai_autofill", async (route) => {
    searches++
    await route.fulfill({ status: 503, json: { status: "error", error_code: "openai_unavailable" } })
  })
  await register(page)
  await page.getByRole("button", { name: "AIで店舗情報を自動入力", exact: true }).click()
  await expect(page.getByText("AI入力を利用できませんでした。手入力で続けられます", { exact: true })).toBeVisible()
  await expect(page.locator(".store-ai-autofill__badge:visible")).toHaveCount(0)
  await page.getByRole("button", { name: "店舗情報を保存して公開する", exact: true }).click()
  await expect(page).toHaveURL(/\/stores\/registration\/thanks$/)
  expect(searches).toBe(1)
})

for (const [name, viewport] of [["desktop", { width: 1440, height: 1000 }], ["mobile", { width: 390, height: 844 }]]) {
  test(`${name}: AI image preview survives re-search and failed save and is published explicitly`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport)
    const errors = []
    page.on("pageerror", (error) => errors.push(error.message))
    let imageRequests = 0
    let searches = 0
    await page.route("**/admin/stores/*/ai_autofill", async (route) => {
      searches++
      await route.fulfill({ json: { ...result({ area: "渋谷" }), image_token: "test-signed-token" } })
    })
    await page.route("**/ai_autofill/image", async (route) => {
      imageRequests++
      expect(route.request().postDataJSON()).toEqual({ image_token: "test-signed-token" })
      await route.fulfill({
        contentType: "image/jpeg", body: require("node:fs").readFileSync(path.resolve(__dirname, "../../test/fixtures/files/sample.jpg")),
        headers: { "X-Image-Source-Url": "https://example.com/official-store" }
      })
    })
    await register(page)
    await page.getByRole("button", { name: "AIで店舗情報を自動入力", exact: true }).click()
    const operation = page.locator('[data-image-attachment-editor-target="operationInput"]')
    const preview = page.locator('[data-image-attachment-editor-target="currentPreview"]')
    await expect(operation).toHaveValue("replace")
    await expect(preview).toBeVisible()
    await expect(page.locator("dialog[open]")).toHaveCount(0)
    await page.getByText("AIが参照した情報", { exact: true }).click()
    await expect(page.getByRole("link", { name: "店舗画像の掲載元" })).toHaveAttribute("href", "https://example.com/official-store")
    const previewUrl = await preview.getAttribute("src")
    await page.getByRole("button", { name: "AIで再検索", exact: true }).click()
    await expect(page.locator('[data-store-ai-autofill-target="loading"]')).toBeHidden()
    expect(imageRequests).toBe(1)
    await expect(preview).toHaveAttribute("src", previewUrl)
    await page.getByLabel("地域", { exact: true }).fill("長".repeat(51))
    const publish = page.getByRole("button", { name: "店舗情報を保存して公開する", exact: true })
    await publish.click()
    await expect(page.locator('[data-image-pair-form-target="error"]')).toBeVisible()
    await expect(operation).toHaveValue("replace")
    await expect(preview).toHaveAttribute("src", previewUrl)
    await page.getByLabel("地域", { exact: true }).fill("画像確認用")
    await page.screenshot({ path: testInfo.outputPath(`${name}-ai-image.png`), fullPage: true })
    await publish.click()
    await expect(page).toHaveURL(/\/stores\/registration\/thanks$/)
    expect(searches).toBe(2)
    expect(imageRequests).toBe(1)
    expect(errors).toEqual([])
  })
}

test("image download failure keeps the successful text result and permits publication", async ({ page }) => {
  await page.route("**/admin/stores/*/ai_autofill", (route) => route.fulfill({
    json: { ...result({ area: "保持する地域" }), image_token: "test-signed-token" }
  }))
  await page.route("**/ai_autofill/image", (route) => route.fulfill({ status: 503 }))
  await register(page)
  await page.getByRole("button", { name: "AIで店舗情報を自動入力", exact: true }).click()
  await expect(page.getByLabel("地域", { exact: true })).toHaveValue("保持する地域")
  await expect(badge(page, "area")).toHaveText(/AI/)
  await expect(page.locator('[data-image-attachment-editor-target="operationInput"]')).toHaveValue("")
  await page.getByRole("button", { name: "店舗情報を保存して公開する", exact: true }).click()
  await expect(page).toHaveURL(/\/stores\/registration\/thanks$/)
})
