const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function loadNormalizer(overrides = {}) {
  const source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/image_attachments/source_normalizer.js"), "utf8")
    .replaceAll("export ", "")
  const context = vm.createContext({
    performance,
    DOMException,
    AbortController,
    Blob,
    File,
    ...overrides,
  })
  vm.runInContext(`${source}\nglobalThis.api = {
    IMAGE_SOURCE_LIMITS,
    ImageSourceNormalizer,
    inspectImageSourceHeader,
    planEditingSourceSize,
    validateImageSourceDimensions,
  }`, context)
  return context.api
}

function pngHeader(width, height) {
  const buffer = Buffer.alloc(33)
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(buffer)
  buffer.writeUInt32BE(13, 8)
  buffer.write("IHDR", 12)
  buffer.writeUInt32BE(width, 16)
  buffer.writeUInt32BE(height, 20)
  return buffer
}

function pngFile(width = 320, height = 180, options = {}) {
  return new File([pngHeader(width, height)], options.name || "fixture.png", {
    type: options.type || "image/png",
  })
}

function arrayBuffer(buffer) {
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength)
}

function canvasFactory({ canvases = [] } = {}) {
  return () => {
    const canvas = {
      width: 0,
      height: 0,
      getContext: () => ({
        fillRect() {},
        drawImage() {},
        getContextAttributes: () => ({ colorSpace: "srgb" }),
      }),
      toBlob: (callback) => callback(new Blob(["jpeg"], { type: "image/jpeg" })),
    }
    canvases.push(canvas)
    return canvas
  }
}

function errorCode(error) {
  return error?.code
}

test("small images are enlarged for each purpose and large images use the fixed output limits", () => {
  const { IMAGE_SOURCE_LIMITS, planEditingSourceSize } = loadNormalizer()
  for (const ratioKey of ["square", "social"]) {
    for (const [width, height] of [[320, 180], [180, 320], [100, 100], [1421, 800]]) {
      const actual = planEditingSourceSize({ width, height, ratioKey })
      const minimum = ratioKey === "square" ? [1024, 1024] : [1200, 630]
      const scale = Math.max(1, minimum[0] / width, minimum[1] / height)
      assert.equal(actual.scale, scale)
      assert.ok(actual.width >= minimum[0] && actual.height >= minimum[1])
      assert.ok(Math.abs(actual.width - width * scale) <= 1)
      assert.ok(Math.abs(actual.height - height * scale) <= 1)
    }
  }

  const large = planEditingSourceSize({ width: 6000, height: 4000, ratioKey: "social" })
  assert.equal(large.reduced, true)
  assert.ok(large.width <= IMAGE_SOURCE_LIMITS.outputEdge)
  assert.ok(large.width * large.height <= IMAGE_SOURCE_LIMITS.outputPixels)
  assert.equal(IMAGE_SOURCE_LIMITS.quality, 0.94)
})

test("unsafe, extreme, incompatible and unknown-purpose dimensions have stable error codes", () => {
  const { planEditingSourceSize, validateImageSourceDimensions } = loadNormalizer()
  for (const [width, height, code] of [
    [0, 10, "dimensions_unreadable"],
    [NaN, 10, "dimensions_unreadable"],
    [10.5, 20, "dimensions_unreadable"],
    [8193, 3000, "dimensions_too_large"],
    [6000, 6000, "dimensions_too_large"],
    [1000, 10, "aspect_ratio_too_large"],
  ]) {
    assert.throws(() => validateImageSourceDimensions(width, height), (error) => errorCode(error) === code)
  }
  assert.throws(
    () => planEditingSourceSize({ width: 100, height: 800, ratioKey: "social" }),
    (error) => errorCode(error) === "incompatible_dimensions"
  )
  assert.throws(
    () => planEditingSourceSize({ width: 320, height: 180, ratioKey: "unknown" }),
    (error) => errorCode(error) === "invalid_purpose"
  )
})

test("PNG, JPEG SOF and all WebP header variants are recognized; corrupt headers are rejected", () => {
  const { inspectImageSourceHeader } = loadNormalizer()
  assert.equal(inspectImageSourceHeader(arrayBuffer(pngHeader(320, 180))).mimeType, "image/png")
  const jpeg = new Uint8Array([255, 216, 255, 224, 0, 2, 255, 194, 0, 8, 8, 0, 180, 1, 64, 1])
  assert.equal(inspectImageSourceHeader(jpeg.buffer).width, 320)
  for (const type of ["VP8X", "VP8 ", "VP8L"]) {
    const buffer = Buffer.alloc(32)
    buffer.write("RIFF", 0)
    buffer.write("WEBP", 8)
    buffer.write(type, 12)
    if (type === "VP8X") { buffer.writeUIntLE(319, 24, 3); buffer.writeUIntLE(179, 27, 3) }
    if (type === "VP8 ") { Buffer.from([157, 1, 42]).copy(buffer, 23); buffer.writeUInt16LE(320, 26); buffer.writeUInt16LE(180, 28) }
    if (type === "VP8L") { buffer[20] = 47; buffer.writeUInt32LE(319 + (179 << 14), 21) }
    const header = inspectImageSourceHeader(arrayBuffer(buffer))
    assert.equal(header.width, 320)
    assert.equal(header.height, 180)
  }
  for (const buffer of [Buffer.alloc(0), Buffer.from([255, 216, 255, 224, 255, 255]), Buffer.from("not a jpg")]) {
    assert.throws(
      () => inspectImageSourceHeader(arrayBuffer(buffer)),
      (error) => errorCode(error) === "unsupported_image"
    )
  }
})

test("oversized byte and pixel inputs are rejected before decoding", async () => {
  let decodeCount = 0
  const { ImageSourceNormalizer } = loadNormalizer({
    createImageBitmap: () => { decodeCount += 1 },
  })
  const normalizer = new ImageSourceNormalizer()
  const oversized = new File([new Uint8Array(20 * 1024 ** 2 + 1)], "large.png", { type: "image/png" })
  await assert.rejects(
    normalizer.normalize(oversized, { ratioKey: "square" }),
    (error) => errorCode(error) === "file_too_large"
  )
  await assert.rejects(
    normalizer.normalize(pngFile(6000, 6000), { ratioKey: "square" }),
    (error) => errorCode(error) === "dimensions_too_large"
  )
  assert.equal(decodeCount, 0)
})

test("canvas failures and null JPEG results close decoded resources and allow retry", async () => {
  for (const failure of ["context", "blob"]) {
    let closed = 0
    let attempt = 0
    const canvases = []
    const createCanvas = canvasFactory({ canvases })
    const { ImageSourceNormalizer } = loadNormalizer({
      createImageBitmap: async () => ({
        width: 320,
        height: 180,
        close: () => { closed += 1 },
      }),
      document: {
        createElement: () => {
          attempt += 1
          const canvas = createCanvas()
          if (attempt === 1 && failure === "context") canvas.getContext = () => null
          if (attempt === 1 && failure === "blob") canvas.toBlob = (callback) => callback(null)
          return canvas
        },
      },
    })
    const normalizer = new ImageSourceNormalizer()
    await assert.rejects(
      normalizer.normalize(pngFile(), { ratioKey: "social" }),
      (error) => errorCode(error) === (failure === "context" ? "canvas_unavailable" : "encode_failed")
    )
    const result = await normalizer.normalize(pngFile(), { ratioKey: "social" })
    assert.equal(result.file.name, "source.jpg")
    assert.equal(result.file.type, "image/jpeg")
    assert.equal(result.warning.code, "source_enlarged")
    assert.equal(closed, 2)
    assert.ok(canvases.every((canvas) => canvas.width === 0 && canvas.height === 0))
  }
})

test("decoder uses the inspected MIME and EXIF fallback releases its object URL", async () => {
  const revoked = []
  let cleared = false
  let decodedType
  const canvases = []
  const { ImageSourceNormalizer } = loadNormalizer({
    createImageBitmap: async (blob) => {
      decodedType = blob.type
      throw new DOMException("decode", "InvalidStateError")
    },
    Image: class {
      naturalWidth = 320
      naturalHeight = 180
      async decode() {}
      removeAttribute() { cleared = true }
    },
    URL: {
      createObjectURL: () => "blob:fallback",
      revokeObjectURL: (url) => revoked.push(url),
    },
    document: { createElement: canvasFactory({ canvases }) },
  })
  const normalizer = new ImageSourceNormalizer()
  const result = await normalizer.normalize(
    pngFile(320, 180, { type: "wrong/type" }),
    { ratioKey: "social" }
  )
  assert.equal(decodedType, "image/png")
  assert.equal(result.decoded.method, "HTMLImageElement")
  assert.equal(result.source.width, 1200)
  assert.equal(result.source.height, 675)
  assert.equal(result.source.quality, 0.94)
  assert.equal(cleared, true)
  assert.deepEqual(revoked, ["blob:fallback"])
})

test("new generations are serialized, superseded results are rejected, and disposal releases resources", async () => {
  let finishFirstDecode
  let finishThirdDecode
  let markFirstStarted
  let markThirdStarted
  const firstStarted = new Promise((resolve) => { markFirstStarted = resolve })
  const thirdStarted = new Promise((resolve) => { markThirdStarted = resolve })
  let activeDecodes = 0
  let maximumActiveDecodes = 0
  let decodeCount = 0
  let closed = 0
  const canvases = []
  const { ImageSourceNormalizer } = loadNormalizer({
    createImageBitmap: async () => {
      decodeCount += 1
      activeDecodes += 1
      maximumActiveDecodes = Math.max(maximumActiveDecodes, activeDecodes)
      if (decodeCount === 1) {
        markFirstStarted()
        await new Promise((resolve) => { finishFirstDecode = resolve })
      }
      if (decodeCount === 3) {
        markThirdStarted()
        await new Promise((resolve) => { finishThirdDecode = resolve })
      }
      activeDecodes -= 1
      return { width: 320, height: 180, close: () => { closed += 1 } }
    },
    document: { createElement: canvasFactory({ canvases }) },
  })
  const normalizer = new ImageSourceNormalizer()
  const first = normalizer.normalize(pngFile(), { ratioKey: "square" })
  await firstStarted
  const second = normalizer.normalize(pngFile(), { ratioKey: "social" })
  finishFirstDecode()

  await assert.rejects(first, (error) => errorCode(error) === "aborted")
  const latest = await second
  assert.equal(latest.source.width, 1200)
  assert.equal(maximumActiveDecodes, 1)
  assert.equal(closed, 2)

  const third = normalizer.normalize(pngFile(), { ratioKey: "square" })
  await thirdStarted
  normalizer.dispose()
  finishThirdDecode()
  await assert.rejects(third, (error) => errorCode(error) === "aborted")
  assert.equal(maximumActiveDecodes, 1)
  assert.equal(closed, 3)
  assert.ok(canvases.every((canvas) => canvas.width === 0 && canvas.height === 0))
})

test("animated PNG and WebP are explicitly rejected", () => {
  const { inspectImageSourceHeader } = loadNormalizer()
  const png = Buffer.concat([pngHeader(320, 180), Buffer.alloc(20)])
  png.writeUInt32BE(8, 33)
  png.write("acTL", 37)
  const webp = Buffer.alloc(30)
  webp.write("RIFF", 0)
  webp.write("WEBP", 8)
  webp.write("VP8X", 12)
  webp[20] = 2
  for (const buffer of [png, webp]) {
    assert.throws(
      () => inspectImageSourceHeader(arrayBuffer(buffer)),
      (error) => errorCode(error) === "animated_image"
    )
  }
})
