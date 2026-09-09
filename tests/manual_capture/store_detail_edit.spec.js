const { test, expect } = require("@playwright/test")

// Create local-only accounts and use real Rails saves without external AI calls.
test.setTimeout(90_000)
test.beforeEach(async ({ baseURL }) => {
  expect(["localhost", "127.0.0.1"]).toContain(new URL(baseURL).hostname)
})

const field = (page, name) => page.locator(`[name="store[${name}]"]`)
const save = (page) => page.locator(".store-edit__bottom-save")
const edit = (page) => page.getByRole("link", { name: "店舗情報を編集", exact: true })

async function confirmSave(page) {
  page.once("dialog", (dialog) => dialog.accept())
  await save(page).click()
}

for (const [device, viewport] of [
  ["desktop", { width: 1440, height: 1000 }],
  ["mobile", { width: 390, height: 844 }]
]) {
  test(`${device}: detail edit, discard, failed save, retry and unpublish return correctly`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport)
    const errors = []
    page.on("pageerror", (error) => errors.push(error.message))
    const storeName = "店舗詳細から編集できることを確認する長い名前のお店 熊本中央店"

    await page.goto("/stores/new_registration")
    await page.getByLabel("店舗名（必須）", { exact: true }).fill(storeName)
    await page.getByLabel("店舗管理者のメールアドレス").fill(
      `detail-edit-${Date.now()}-${Math.random().toString(36).slice(2)}@example.test`
    )
    await page.getByLabel("パスワード（必須）", { exact: true }).fill("SetupTest123!")
    await page.getByLabel("パスワード（確認・必須）").fill("SetupTest123!")
    await page.getByRole("button", { name: "登録して店舗設定へ進む" }).click()
    await expect(page).toHaveURL(/registration_setup\/edit$/, { timeout: 20_000 })
    const storeId = new URL(page.url()).pathname.match(/\/stores\/(\d+)\//)[1]
    const detailPath = `/stores/${storeId}`
    const detailUrl = new URL(detailPath, page.url()).href
    const editPath = `/admin/stores/${storeId}/edit`
    const detailEditUrl = new URL(`${editPath}?return_to=store_detail`, page.url()).href

    await page.goto(editPath)
    await expect(save(page)).toBeDisabled()
    await field(page, "description").fill("保存済みの紹介文")
    await field(page, "published").selectOption("true")
    await confirmSave(page)
    await expect(page).toHaveURL(/\/dashboard$/, { timeout: 20_000 })

    await page.goto(detailPath)
    await expect(edit(page)).toBeVisible()
    await expect(edit(page)).toHaveAttribute("href", `${editPath}?return_to=store_detail`)
    await page.screenshot({ path: testInfo.outputPath(`${device}-detail.png`), fullPage: true })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    if (device === "mobile") {
      await page.setViewportSize({ width: 320, height: 740 })
      await expect(edit(page)).toBeVisible()
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
      await page.screenshot({ path: testInfo.outputPath("mobile-320-detail.png"), fullPage: true })
      await page.setViewportSize(viewport)
    }

    await edit(page).click()
    await expect(page).toHaveURL(detailEditUrl)
    await expect(save(page)).toBeDisabled()
    await expect(page.locator(".store-edit__back")).toHaveAttribute("href", detailPath)
    await page.locator(".store-edit__back").click()
    await expect(page).toHaveURL(detailUrl)

    await edit(page).click()
    await expect(save(page)).toBeDisabled()
    await field(page, "description").fill("破棄する変更")
    page.once("dialog", async (dialog) => {
      expect(dialog.message()).toBe("保存していない変更を破棄しますか？")
      await dialog.dismiss()
    })
    await page.locator(".store-edit__back").click()
    await expect(page).toHaveURL(detailEditUrl)
    await expect(field(page, "description")).toHaveValue("破棄する変更")
    page.once("dialog", (dialog) => dialog.accept())
    await page.locator(".store-edit__back").click()
    await expect(page).toHaveURL(detailUrl)
    await expect(page.locator(".store-show-description")).toContainText("保存済みの紹介文")

    await edit(page).click()
    await expect(save(page)).toBeDisabled()
    await field(page, "description").fill("編集して公開ページに戻った紹介文")
    await field(page, "area").fill("長".repeat(51))
    await confirmSave(page)
    await expect(page.locator('[data-image-pair-form-target="error"]')).toBeVisible()
    await expect(page).toHaveURL(detailEditUrl)
    await expect(field(page, "description")).toHaveValue("編集して公開ページに戻った紹介文")
    await expect(page.locator('[name="return_to"]')).toHaveValue("store_detail")
    await field(page, "area").fill("熊本")
    await confirmSave(page)
    await expect(page).toHaveURL(detailUrl, { timeout: 20_000 })
    await expect(page.locator(".store-show-description")).toContainText("編集して公開ページに戻った紹介文")

    await edit(page).click()
    await expect(save(page)).toBeDisabled()
    await field(page, "published").selectOption("false")
    await confirmSave(page)
    await expect(page).toHaveURL(/\/dashboard$/, { timeout: 20_000 })
    expect(errors).toEqual([])
  })
}
