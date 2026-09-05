const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const browsers = require("@playwright/test")
const { openVerificationPage } = require("./helpers/image_verification_page.cjs")

const root = path.resolve(__dirname, "../../..")

test("real Cropper.js reaches the selection minimum, restores it, and exports without blank borders", async () => {
  const browser = await browsers[process.env.IMAGE_VERIFICATION_BROWSER || "chromium"].launch({ headless: true })
  let environment
  try {
    environment = await openVerificationPage(browser)
    const { page, errors } = environment

    for (const [width, height] of [[1421, 800], [800, 1421]]) {
      for (const ratioKey of ["square", "social"]) {
        const result = await page.evaluate(async ({ width, height, ratioKey }) => {
          const controller = window.verification
          const input = document.createElement("canvas")
          input.width = width
          input.height = height
          const context = input.getContext("2d")
          context.fillStyle = "rgb(20, 80, 160)"
          context.fillRect(0, 0, width, height)
          const blob = await new Promise((resolve) => input.toBlob(resolve, "image/png"))
          controller.ratioTarget.value = ratioKey
          await controller.loadFile({ currentTarget: { files: [new File([blob], "test.png", { type: "image/png" })] } })
          if (!controller.cropperImage) throw new Error(controller.statusTarget.textContent)
          await new Promise(requestAnimationFrame)
          for (let index = 0; index < 30; index += 1) controller.zoomOut()
          controller.cropperImage.$move(10000, -10000)
          const minimum = controller.captureState()
          for (let index = 0; index < 10; index += 1) controller.zoomOut()
          const repeated = controller.captureState()
          controller.zoomIn()
          controller.zoomIn()
          controller.stateTarget.value = JSON.stringify(minimum)
          await controller.restoreState()
          const restored = JSON.parse(controller.stateTarget.value)
          // Let the new src request replace the previous preview before decode().
          await new Promise(requestAnimationFrame)
          await controller.previewTarget.decode()
          const output = document.createElement("canvas")
          output.width = controller.previewTarget.naturalWidth
          output.height = controller.previewTarget.naturalHeight
          const outputContext = output.getContext("2d")
          outputContext.drawImage(controller.previewTarget, 0, 0)
          const corners = [[0, 0], [output.width - 1, 0], [0, output.height - 1], [output.width - 1, output.height - 1]]
            .map(([x, y]) => Array.from(outputContext.getImageData(x, y, 1, 1).data))
          return {
            minimum, repeated, restored, corners,
            output: { width: output.width, height: output.height },
            status: controller.statusTarget.textContent,
          }
        }, { width, height, ratioKey })

        assert.ok(result.minimum.crop.width === result.minimum.source.width || result.minimum.crop.height === result.minimum.source.height)
        assert.deepEqual(result.repeated.crop, result.minimum.crop)
        for (const key of ["x", "y", "width", "height"]) {
          assert.ok(Math.abs(result.restored.crop[key] - result.minimum.crop[key]) < 0.001)
        }
        assert.deepEqual(result.output, ratioKey === "square" ? { width: 1024, height: 1024 } : { width: 1200, height: 630 })
        assert.equal(result.status, "JSONのクロップ状態を復元しました")
        for (const corner of result.corners) {
          assert.ok(Math.abs(corner[0] - 20) < 20 && Math.abs(corner[1] - 80) < 20 && Math.abs(corner[2] - 160) < 20)
        }
      }
    }
    const lifecycle = await page.evaluate(async () => {
      const controller = window.verification
      const canvas = document.createElement("canvas")
      canvas.width = 320
      canvas.height = 180
      const context = canvas.getContext("2d")
      context.fillStyle = "#336699"
      context.fillRect(0, 0, 320, 180)
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"))
      const file = new File([blob], "small.png", { type: "image/png" })
      const load = () => controller.loadFile({ currentTarget: { files: [file] } })
      controller.ratioTarget.value = "square"
      await load()
      const square = JSON.parse(controller.normalizationReportTarget.value)
      const warning = controller.normalizationWarningTarget.textContent
      controller.ratioTarget.value = "social"
      await controller.changeRatio()
      const social = JSON.parse(controller.normalizationReportTarget.value)
      const firstJpeg = Array.from(new Uint8Array(await (await fetch(controller.sourceObjectUrl)).arrayBuffer()))
      await controller.normalizeSource()
      const secondJpeg = Array.from(new Uint8Array(await (await fetch(controller.sourceObjectUrl)).arrayBuffer()))
      const unchangedInput = JSON.parse(controller.normalizationReportTarget.value).input

      const originalDecode = window.createImageBitmap
      let active = 0
      let maximumActive = 0
      let signalDecode
      const decoding = new Promise((resolve) => { signalDecode = resolve })
      window.createImageBitmap = async (...args) => {
        active += 1
        maximumActive = Math.max(maximumActive, active)
        signalDecode()
        await new Promise((resolve) => setTimeout(resolve, 30))
        try { return await originalDecode(...args) } finally { active -= 1 }
      }
      const first = load()
      await decoding
      controller.ratioTarget.value = "square"
      const second = controller.changeRatio()
      controller.ratioTarget.value = "social"
      const latest = controller.changeRatio()
      await Promise.all([first, second, latest])
      const latestState = JSON.parse(controller.stateTarget.value)

      const beforeReconnect = load()
      await new Promise((resolve) => setTimeout(resolve, 10))
      controller.disconnect()
      controller.connect()
      controller.ratioTarget.value = "square"
      const afterReconnect = load()
      await Promise.all([beforeReconnect, afterReconnect])
      const reconnectedState = JSON.parse(controller.stateTarget.value)

      const pending = load()
      await new Promise((resolve) => setTimeout(resolve, 10))
      controller.beforeCache()
      await pending
      window.createImageBitmap = originalDecode
      const cleaned = !controller.sourceObjectUrl && !controller.previewObjectUrl && !controller.selectedFile &&
        !controller.sourceDownloadTarget.hasAttribute("href") && controller.normalizedPreviewTarget.hidden

      const corrupt = new File(["not an image"], "invalid.jpg", { type: "image/jpeg" })
      await controller.loadFile({ currentTarget: { files: [corrupt] } })
      const failure = { status: controller.statusTarget.textContent, cropper: !!controller.cropper,
        download: controller.sourceDownloadTarget.hasAttribute("href"), disabled: controller.controlTargets.every((element) => element.disabled) }
      await load()
      return { square, social, warning, firstJpeg, secondJpeg, unchangedInput, maximumActive, latestState, reconnectedState, cleaned, failure,
        recovered: !!controller.cropper && controller.sourceDownloadTarget.hasAttribute("href") }
    })
    assert.equal(lifecycle.square.source.width, 1820)
    assert.equal(lifecycle.square.source.height, 1024)
    assert.equal(lifecycle.social.source.width, 1200)
    assert.equal(lifecycle.social.source.height, 675)
    assert.match(lifecycle.warning, /細部の解像感は増えません/)
    assert.deepEqual(lifecycle.firstJpeg, lifecycle.secondJpeg, "reprocessing must restart from the original input")
    assert.deepEqual(lifecycle.unchangedInput, lifecycle.social.input)
    assert.equal(lifecycle.maximumActive, 1)
    assert.equal(lifecycle.latestState.ratioKey, "social")
    assert.deepEqual(lifecycle.latestState.source, { width: 1200, height: 675 })
    assert.equal(lifecycle.reconnectedState.ratioKey, "square")
    assert.deepEqual(lifecycle.reconnectedState.source, { width: 1820, height: 1024 })
    assert.equal(lifecycle.cleaned, true)
    assert.match(lifecycle.failure.status, /画像実体/)
    assert.equal(lifecycle.failure.cropper, false)
    assert.equal(lifecycle.failure.download, false)
    assert.equal(lifecycle.failure.disabled, true)
    assert.equal(lifecycle.recovered, true)
    assert.deepEqual(errors, [])
    if (process.env.IMAGE_VERIFICATION_SCREENSHOT) {
      await page.addStyleTag({ content: fs.readFileSync(path.join(root, "app/assets/builds/application.css"), "utf8").replace(/@import[^;]+;/g, "") })
      await page.addStyleTag({ content: ".image-upload-verification__editor { width: 100%; }" })
      await page.screenshot({ path: process.env.IMAGE_VERIFICATION_SCREENSHOT, fullPage: true })
    }
  } finally {
    await environment?.close()
    await browser.close()
  }
})
