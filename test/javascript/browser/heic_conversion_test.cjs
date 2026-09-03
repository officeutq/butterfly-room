const assert = require("node:assert/strict")
const test = require("node:test")
const browsers = require("@playwright/test")
const { openVerificationPage } = require("./helpers/image_verification_page.cjs")

test("HEIC conversion, crop and cancellation use same-origin lazy modules under strict CSP", { timeout: 120_000 }, async (t) => {
  const browserName = process.env.IMAGE_VERIFICATION_BROWSER || "chromium"
  const browser = await browsers[browserName].launch({ headless: true })
  let environment
  try {
    environment = await openVerificationPage(browser, { strictCsp: true })
    const { page, requests, errors } = environment
    assert.ok(!requests.includes("/decoder.js") && !requests.includes("/worker.js"), "HEIC assets must be lazy-loaded")
    const results = await page.evaluate(async () => {
      const controller = window.verification
      const NativeWorker = window.Worker
      let activeWorkers = 0
      window.Worker = class extends NativeWorker {
        constructor(...args) { super(...args); activeWorkers += 1 }
        terminate() { activeWorkers -= 1; super.terminate() }
      }
      const sample = await (await fetch("/sample.heic")).blob()
      const file = new File([sample], "sample.heic", { type: "image/heic" })
      const results = []
      for (const mode of ["worker", "main"]) {
        controller.heicModeTarget.value = mode
        controller.ratioTarget.value = mode === "worker" ? "social" : "square"
        await controller.loadFile({ currentTarget: { files: [file] } })
        if (!controller.cropperImage) throw new Error(controller.statusTarget.textContent)
        await new Promise(requestAnimationFrame)
        const report = JSON.parse(controller.normalizationReportTarget.value)
        const state = controller.captureState()
        controller.zoomIn()
        controller.stateTarget.value = JSON.stringify(state)
        await controller.restoreState()
        results.push({ report, state, restored: controller.captureState(), preview: (await (await fetch(controller.previewObjectUrl)).blob()).type })
      }
      controller.heicModeTarget.value = "worker"
      const pending = controller.loadFile({ currentTarget: { files: [file] } })
      for (let attempt = 0; activeWorkers === 0 && attempt < 100; attempt += 1) await new Promise((resolve) => setTimeout(resolve, 2))
      if (!activeWorkers) throw new Error("Cancellation must reach a real active Worker")
      controller.cancelConversion()
      await pending
      const cancelled = activeWorkers === 0 && !controller.cropper && !controller.sourceObjectUrl && controller.cancelConversionTarget.disabled
      const bad = new File(["broken"], "corrupt.heif", { type: "image/heif" })
      await controller.loadFile({ currentTarget: { files: [bad] } })
      const error = controller.statusTarget.textContent
      const noFallback = !controller.cropper && !controller.sourceObjectUrl && !controller.sourceDownloadTarget.hasAttribute("href")
      // Valid ftyp, but no image items: error must come from the native decoder.
      await controller.loadFile({ currentTarget: { files: [new File([sample.slice(0, 32)], "truncated.heic", { type: "image/heic" })] } })
      const decoderError = controller.statusTarget.textContent
      const decoderFailedClosed = !controller.cropper && activeWorkers === 0
      const leaving = controller.loadFile({ currentTarget: { files: [file] } })
      for (let attempt = 0; activeWorkers === 0 && attempt < 100; attempt += 1) await new Promise((resolve) => setTimeout(resolve, 2))
      if (!activeWorkers) throw new Error("Leaving must reach a real active Worker")
      controller.beforeCache()
      controller.disconnect()
      controller.connect()
      await leaving
      const leftClean = !controller.cropper && activeWorkers === 0
      await controller.loadFile({ currentTarget: { files: [file] } })
      const recovered = !!controller.cropper && activeWorkers === 0
      window.Worker = NativeWorker
      return { results, cancelled, error, noFallback, decoderError, decoderFailedClosed, leftClean, recovered }
    })
    for (const result of results.results) {
      assert.equal(result.report.heicConversion.width, 48)
      assert.equal(result.report.heicConversion.height, 32)
      assert.equal(result.report.heicConversion.imageCount, 1)
      assert.equal(result.report.heicConversion.selectedImageIndex, 0)
      assert.equal(result.report.input.mimeType, "image/jpeg")
      assert.equal(result.preview, "image/jpeg")
      assert.deepEqual(result.restored.crop, result.state.crop)
      t.diagnostic(JSON.stringify(result.report.heicConversion))
    }
    assert.equal(results.cancelled, true)
    assert.match(results.error, /実体/)
    assert.equal(results.noFallback, true)
    assert.match(results.decoderError, /静止画像/)
    assert.equal(results.decoderFailedClosed, true)
    assert.equal(results.leftClean, true)
    assert.equal(results.recovered, true)
    const initialPreview = await page.evaluate(async () => {
      const controller = window.verification
      controller.ratioTarget.value = "square"
      const input = await (await fetch("/heic/rotated.heif")).blob()
      await controller.loadFile({ currentTarget: { files: [new File([input], "rotated.heif")] } })
      await controller.previewTarget.decode()
      const canvas = document.createElement("canvas")
      canvas.width = 1024
      canvas.height = 1024
      const context = canvas.getContext("2d")
      const sample = () => [[256, 256], [768, 256], [256, 768], [768, 768]].map(([x, y]) => Array.from(context.getImageData(x, y, 1, 1).data))
      context.drawImage(controller.previewTarget, 0, 0)
      const initial = sample()
      await new Promise(requestAnimationFrame)
      await controller.generatePreview()
      await controller.previewTarget.decode()
      context.drawImage(controller.previewTarget, 0, 0)
      return { initial, regenerated: sample() }
    })
    assert.deepEqual(initialPreview.initial, initialPreview.regenerated, "initial export must wait for Cropper centering, not require a second click")
    const samples = await page.evaluate(async () => {
      const samples = []
      for (const [name, mode] of [["medium.heic", "worker"], ["medium.heic", "main"], ["large.heic", "worker"], ["rotated.heif", "worker"], ["alpha.heic", "worker"], ["multiple.heic", "worker"]]) {
        const input = await (await fetch(`/heic/${name}`)).blob()
        const { file, conversion } = await window.prepareHeicInput(new File([input], name, { type: "" }), {
          workerUrl: new URL("/worker.js", location).href, decoderUrl: new URL("/decoder.js", location).href, mode,
        })
        if (new TextDecoder("latin1").decode(await file.arrayBuffer()).includes("Exif\0\0")) throw new Error("Source EXIF must not survive JPEG encoding")
        const url = URL.createObjectURL(file)
        const image = new Image()
        try {
          image.src = url
          await image.decode()
          const canvas = document.createElement("canvas")
          canvas.width = image.naturalWidth
          canvas.height = image.naturalHeight
          const context = canvas.getContext("2d")
          context.drawImage(image, 0, 0)
          const colors = [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]].map(([x, y]) =>
            Array.from(context.getImageData(Math.floor(x * canvas.width), Math.floor(y * canvas.height), 1, 1).data))
          samples.push({ name, conversion, width: image.naturalWidth, height: image.naturalHeight, colors })
          canvas.width = 0
          canvas.height = 0
        } finally { image.removeAttribute("src"); URL.revokeObjectURL(url) }
      }
      return samples
    })
    const colors = { red: [255, 0, 0, 255], green: [0, 255, 0, 255], blue: [0, 0, 255, 255], yellow: [255, 255, 0, 255], white: [255, 255, 255, 255] }
    for (const sample of samples) {
      const expected = {
        "medium.heic": [1200, 800, ["red", "green", "blue", "yellow"]],
        "large.heic": [4000, 3000, ["red", "green", "blue", "yellow"]],
        "rotated.heif": [96, 160, ["blue", "red", "yellow", "green"]],
        "alpha.heic": [96, 64, ["white", "red", "white", "red"]],
        "multiple.heic": [96, 64, ["red", "red", "red", "red"]],
      }[sample.name]
      assert.deepEqual([sample.width, sample.height], expected.slice(0, 2), sample.name)
      expected[2].forEach((color, index) => sample.colors[index].forEach((value, channel) =>
        assert.ok(Math.abs(value - colors[color][channel]) < 25, `${sample.name} ${color}: ${sample.colors[index]}`)))
      if (sample.name === "multiple.heic") assert.equal(sample.conversion.imageCount, 2)
      assert.equal(sample.conversion.memory.rgbaBytes, sample.width * sample.height * 4)
      assert.equal(sample.conversion.memory.peakBytes, null, "RGBA estimate is not a peak measurement")
      t.diagnostic(JSON.stringify(sample.conversion))
    }
    assert.deepEqual(errors, [])
    t.diagnostic(`${browserName} ${browser.version()}`)
  } finally {
    await environment?.close()
    await browser.close()
  }
})
