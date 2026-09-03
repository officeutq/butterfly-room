const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const browsers = require("@playwright/test")

const normalizer = fs.readFileSync(path.resolve(__dirname, "../../../app/javascript/controllers/image_upload_verification/source_normalizer.js"), "utf8")

test("browser normalization: three formats, EXIF 1–8, transparency, metadata and quality/size measurements", async (t) => {
  const browserName = process.env.IMAGE_VERIFICATION_BROWSER || "chromium"
  const browser = await browsers[browserName].launch({ headless: true })
  try {
    const page = await browser.newPage()
    await page.route("http://normalizer.test/**", (route) => route.fulfill(new URL(route.request().url()).pathname === "/normalizer.js"
      ? { contentType: "text/javascript", body: normalizer }
      : { contentType: "text/html", body: '<script type="module">import { normalizeEditingSource } from "/normalizer.js"; window.normalize = normalizeEditingSource</script>' }))
    await page.goto("http://normalizer.test/")
    await page.waitForFunction(() => !!window.normalize)
    const results = await page.evaluate(async () => {
      const canvasBlob = (canvas, type) => new Promise((resolve) => canvas.toBlob(resolve, type, 0.94))
      const fixture = async (width, height, type, transparent = false, texture = false) => {
        const canvas = document.createElement("canvas")
        canvas.width = width
        canvas.height = height
        const context = canvas.getContext("2d")
        if (texture) {
          const gradient = context.createLinearGradient(0, 0, width, height)
          gradient.addColorStop(0, "#206070")
          gradient.addColorStop(1, "#efa255")
          context.fillStyle = gradient
          context.fillRect(0, 0, width, height)
          let seed = 7
          for (let index = 0; index < 20_000; index += 1) {
            seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0
            context.fillStyle = `rgba(${seed & 255},${(seed >>> 8) & 255},${(seed >>> 16) & 255},0.5)`
            context.fillRect(seed % width, (seed >>> 12) % height, 4, 4)
          }
          context.fillStyle = "white"
          context.font = "40px sans-serif"
          context.fillText("Source JPEG / 0123456789", 20, 60)
        } else {
          for (const [index, color] of ["#f00000", "#00f000", "#0000f0", "#f0f000"].entries()) {
            if (transparent && index === 3) continue
            context.fillStyle = color
            context.fillRect((index % 2) * width / 2, Math.floor(index / 2) * height / 2, width / 2, height / 2)
          }
        }
        const blob = await canvasBlob(canvas, type)
        canvas.width = canvas.height = 0
        return new File([blob], `fixture-${width}x${height}.${type.split("/")[1]}`, { type })
      }
      const pixels = async (blob) => {
        const bitmap = await createImageBitmap(blob)
        const canvas = document.createElement("canvas")
        canvas.width = bitmap.width
        canvas.height = bitmap.height
        const context = canvas.getContext("2d")
        context.drawImage(bitmap, 0, 0)
        const colors = [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]].map(([x, y]) =>
          Array.from(context.getImageData(Math.floor(x * canvas.width), Math.floor(y * canvas.height), 1, 1).data))
        bitmap.close()
        canvas.width = canvas.height = 0
        return colors
      }
      const hasApp1 = async (blob) => {
        const view = new DataView(await blob.arrayBuffer())
        let offset = 2
        while (offset + 4 < view.byteLength && view.getUint8(offset) === 255) {
          const marker = view.getUint8(offset + 1)
          if (marker === 225) return true
          if (marker === 218 || marker === 217) break
          offset += 2 + view.getUint16(offset + 2)
        }
        return false
      }
      const withExif = async (file, orientation) => {
        // Little-endian TIFF: Orientation plus GPSLatitudeRef=N, GPSLatitude=35/1,0/1,0/1.
        const segment = new Uint8Array(102)
        segment.set([255, 225, 0, 100, 69, 120, 105, 102, 0, 0, 73, 73, 42, 0, 8, 0, 0, 0])
        const tiff = new DataView(segment.buffer, 10)
        const entry = (offset, tag, type, count, value) => {
          tiff.setUint16(offset, tag, true); tiff.setUint16(offset + 2, type, true)
          tiff.setUint32(offset + 4, count, true); tiff.setUint32(offset + 8, value, true)
        }
        tiff.setUint16(8, 2, true)
        entry(10, 0x112, 3, 1, orientation)
        entry(22, 0x8825, 4, 1, 38)
        tiff.setUint16(38, 2, true)
        entry(40, 1, 2, 2, 78)
        entry(52, 2, 5, 3, 68)
        tiff.setUint32(68, 35, true)
        for (const offset of [72, 80, 88]) tiff.setUint32(offset, 1, true)
        const jpeg = new Uint8Array(await file.arrayBuffer())
        return new File([jpeg.slice(0, 2), segment, jpeg.slice(2)], `orientation-${orientation}.jpg`, { type: "image/jpeg" })
      }
      const config = { minimumWidth: 1024, minimumHeight: 1024 }
      const formats = []
      for (const type of ["image/jpeg", "image/png", "image/webp"]) {
        const input = await fixture(320, 180, type, type !== "image/jpeg")
        const result = await window.normalize(input, config)
        formats.push({ report: result.report, colors: await pixels(result.blob), app1: await hasApp1(result.blob) })
      }
      const orientations = []
      const jpeg = await fixture(80, 40, "image/jpeg")
      for (let orientation = 1; orientation <= 8; orientation += 1) {
        const input = await withExif(jpeg, orientation)
        const result = await window.normalize(input, config).catch((error) => {
          throw new Error(`EXIF ${orientation}: ${error.message} / ${error.cause?.message}`)
        })
        orientations.push({ orientation, inputApp1: await hasApp1(input), outputApp1: await hasApp1(result.blob), colors: await pixels(result.blob), decoded: result.report.decoded })
      }
      const measurements = []
      const textured = await fixture(1000, 700, "image/png", false, true)
      for (const quality of [0.9, 0.94, 0.98]) {
        const result = await window.normalize(textured, { minimumWidth: 1200, minimumHeight: 630, quality })
        measurements.push(result.report)
      }
      const large = await fixture(6000, 4000, "image/jpeg", false, true)
      for (const mode of ["bounded", "retain"]) {
        const result = await window.normalize(large, { minimumWidth: 1200, minimumHeight: 630, mode })
        measurements.push(result.report)
      }
      return { formats, orientations, measurements }
    })
    const palette = { R: [240, 0, 0], G: [0, 240, 0], B: [0, 0, 240], Y: [240, 240, 0], W: [255, 255, 255] }
    const expectColors = (actual, names) => names.forEach((name, index) => {
      palette[name].forEach((channel, component) => assert.ok(Math.abs(actual[index][component] - channel) < 15, `${name}: ${actual[index]}`))
      assert.equal(actual[index][3], 255)
    })
    for (const result of results.formats) {
      assert.equal(result.report.source.mimeType, "image/jpeg")
      assert.equal(result.report.source.width, 1820)
      assert.equal(result.report.source.height, 1024)
      assert.equal(result.report.source.colorSpace, "srgb")
      assert.equal(result.app1, false)
      expectColors(result.colors, result.report.input.mimeType === "image/jpeg" ? ["R", "G", "B", "Y"] : ["R", "G", "B", "W"])
    }
    const orders = ["RGBY", "GRYB", "YBGR", "BYRG", "RBGY", "BRYG", "YGBR", "GYRB"]
    results.orientations.forEach((result, index) => {
      assert.equal(result.inputApp1, true)
      assert.equal(result.outputApp1, false)
      assert.equal(result.decoded.width, index < 4 ? 80 : 40)
      assert.equal(result.decoded.height, index < 4 ? 40 : 80)
      expectColors(result.colors, [...orders[index]])
    })
    const [q90, q94, q98, bounded, retain] = results.measurements
    assert.ok(q90.source.bytes < q94.source.bytes && q94.source.bytes < q98.source.bytes)
    assert.ok(bounded.source.width <= 4096 && bounded.source.width * bounded.source.height <= 8_000_000)
    assert.equal(retain.source.width, 6000)
    assert.equal(retain.source.height, 4000)
    t.diagnostic(`${browserName} ${browser.version()}`)
    t.diagnostic(`EXIF decode: ${[...new Set(results.orientations.map((result) => result.decoded.method))].join(", ")}`)
    for (const report of [...results.formats.map((item) => item.report), ...results.measurements]) {
      t.diagnostic(JSON.stringify({ input: report.input, source: report.source, mode: report.mode, milliseconds: report.milliseconds }))
    }
  } finally {
    await browser.close()
  }
})
