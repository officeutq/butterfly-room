const test = require("node:test")
const assert = require("node:assert/strict")
const browsers = require("@playwright/test")

const base = process.env.IMAGE_UPLOAD_VERIFICATION_BASE_URL
test("real Rails + Stimulus + Active Storage stores both ratios through both transports", { skip: !base }, async () => {
  assert.ok(["localhost", "127.0.0.1", "app.localhost"].includes(new URL(base).hostname), "local test server only")
  assert.ok(process.env.IMAGE_UPLOAD_VERIFICATION_EMAIL && process.env.IMAGE_UPLOAD_VERIFICATION_PASSWORD, "dedicated local system_admin credentials required")
  const browser = await browsers[process.env.IMAGE_VERIFICATION_BROWSER || "chromium"].launch({ headless: true })
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } })
    const errors = []
    page.on("pageerror", error => errors.push(error.message))
    await page.goto(`${base}/users/sign_in`)
    await page.locator('input[name="user[email]"]').fill(process.env.IMAGE_UPLOAD_VERIFICATION_EMAIL)
    await page.locator('input[name="user[password]"]').fill(process.env.IMAGE_UPLOAD_VERIFICATION_PASSWORD)
    await page.locator('form input[type="submit"], form button[type="submit"]').first().click()
    await page.waitForURL(url => !url.pathname.includes("/users/sign_in"))
    await page.goto(`${base}/system_admin/image_upload_verification`)
    const target = name => page.locator(`[data-image-upload-verification-target~="${name}"]`)
    await page.waitForFunction(() => !!window.Stimulus?.getControllerForElementAndIdentifier(document.querySelector(".image-upload-verification"), "image-upload-verification"))
    const measurements = []
    for (const ratio of ["square", "social"]) {
      await target("ratio").selectOption(ratio)
      // Synthetic four-color PNG, not a user's photo or production attachment.
      const bytes = await page.evaluate(async () => {
        const canvas = document.createElement("canvas")
        canvas.width = 1421; canvas.height = 800
        const ctx = canvas.getContext("2d")
        for (const [color, x, y] of [["red", 0, 0], ["blue", 711, 0], ["green", 0, 400], ["yellow", 711, 400]]) {
          ctx.fillStyle = color; ctx.fillRect(x, y, 711, 400)
        }
        return Array.from(new Uint8Array(await (await new Promise(resolve => canvas.toBlob(resolve, "image/png"))).arrayBuffer()))
      })
      await target("file").setInputFiles({ name: "synthetic.png", mimeType: "image/png", buffer: Buffer.from(bytes) })
      await page.waitForFunction(() => document.querySelector('[data-image-upload-verification-target="status"]').textContent.includes("操作できます"))
      await page.getByRole("button", { name: "拡大", exact: true }).click()
      for (const transport of ["multipart", "direct"]) {
        await target("uploadTransport").selectOption(transport)
        const created = page.waitForResponse(response => response.url().endsWith("/image_upload_verification_runs") && response.request().method() === "POST")
        await target("uploadStart").click()
        const runResponse = await created
        const run = await runResponse.json()
        await page.waitForFunction(() => document.querySelector('[data-image-upload-verification-target="uploadReport"]').value !== "" ||
          document.querySelector('[data-image-upload-verification-target="uploadCancel"]').disabled, { timeout: 30_000 })
        const value = await target("uploadReport").inputValue()
        assert.ok(value, await target("uploadStatus").textContent())
        const report = JSON.parse(value)
        assert.equal(report.state, "complete")
        assert.equal(report.transport, transport)
        assert.equal(report.crop_data.ratioKey, ratio)
        assert.equal(report.images.display.width, ratio === "square" ? 1024 : 1200)
        assert.equal(report.images.display.height, ratio === "square" ? 1024 : 630)
        assert.equal(report.storage, "ActiveStorage::Service::DiskService")
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false)
        measurements.push({ run_id: run.id, ratio, transport, total_bytes: report.total_bytes, server_ms: report.server_milliseconds, client_ms: report.client_milliseconds })
        // Invalidate the test run; actual cleanup remains delayed by design.
        const canceled = await page.evaluate(async id => {
          const response = await fetch(`/system_admin/image_upload_verification_runs/${id}`, { method: "DELETE", headers: {
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          } })
          return response.status
        }, run.id)
        assert.equal(canceled, 200)
      }
    }
    assert.deepEqual(errors, [])
    if (process.env.IMAGE_UPLOAD_VERIFICATION_SCREENSHOT) {
      await target("uploadTransport").scrollIntoViewIfNeeded()
      await page.screenshot({ path: process.env.IMAGE_UPLOAD_VERIFICATION_SCREENSHOT })
    }
    console.log(JSON.stringify({ engine: process.env.IMAGE_VERIFICATION_BROWSER || "chromium", measurements }))
  } finally { await browser.close() }
})
