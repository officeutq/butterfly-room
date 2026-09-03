const test = require("node:test")
const assert = require("node:assert/strict")
const browsers = require("@playwright/test")
const { openVerificationPage } = require("./helpers/image_verification_page.cjs")

test("upload exports a consistent current crop; replacement cancels without stale results", async () => {
  const browser = await browsers[process.env.IMAGE_VERIFICATION_BROWSER || "chromium"].launch({ headless: true })
  const env = await openVerificationPage(browser)
  try {
    const { page } = env
    await page.evaluate(async () => {
      const canvas = document.createElement("canvas")
      canvas.width = 1421; canvas.height = 800
      const ctx = canvas.getContext("2d")
      ctx.fillStyle = "red"; ctx.fillRect(0, 0, 700, 800)
      ctx.fillStyle = "blue"; ctx.fillRect(700, 0, 721, 800)
      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"))
      await window.verification.loadFile({ currentTarget: { files: [new File([blob], "fixture.png", { type: "image/png" })] } })
      window.verification.uploadUrlValue = "/runs"
    })
    let creates = 0, uploads = 0, deletes = 0
    let delay = false
    await page.route("**/runs**", async route => {
      const request = route.request()
      if (request.method() === "DELETE") { deletes++; await route.fulfill({ json: { state: "canceled" } }); return }
      if (request.url().endsWith("/runs")) { creates++; await route.fulfill({ json: { id: creates } }); return }
      uploads++
      const body = request.postDataBuffer().toString("latin1")
      assert.ok(body.includes('name="verification[source]"; filename="source.jpg"'))
      assert.ok(body.includes('name="verification[display]"; filename="display.jpg"'))
      if (delay) await new Promise(resolve => setTimeout(resolve, 700))
      await route.fulfill({ json: { state: "complete", images: {} } }).catch(() => {})
    })
    const result = await page.evaluate(async () => {
      const c = window.verification
      c.zoomIn(); c.zoomIn()
      const expected = c.buildState()
      await c.startUpload()
      return { report: JSON.parse(c.uploadReportTarget.value), expected, disabled: c.uploadStartTarget.disabled }
    })
    assert.deepEqual(result.report.crop_data, result.expected)
    assert.equal(result.disabled, false)
    assert.equal(creates, 1)
    assert.equal(uploads, 1)
    delay = true
    await page.evaluate(() => { window.verification.startUpload() })
    await page.waitForFunction(() => window.verification.uploadClient?.requests.size > 0 && window.verification.uploadClient?.run)
    await page.evaluate(async () => {
      const c = window.verification
      await c.normalizeSource()
    })
    await page.waitForTimeout(850)
    assert.equal(await page.evaluate(() => window.verification.uploadReportTarget.value), "")
    assert.ok(deletes >= 1)
    assert.deepEqual(env.errors, [])
  } finally { await env.close(); await browser.close() }
})
