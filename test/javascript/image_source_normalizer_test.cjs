const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function loadNormalizer(overrides = {}) {
  const source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers/image_upload_verification/source_normalizer.js"), "utf8")
    .replaceAll("export ", "")
  const context = vm.createContext({ performance, DOMException, navigator: { userAgent: "unit-test" }, ...overrides })
  vm.runInContext(`${source}\nglobalThis.api = { planSourceSize, inspectImageHeader, normalizeEditingSource }`, context)
  return context.api
}

function pngHeader(width, height) {
  const buffer = Buffer.alloc(33)
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(buffer)
  buffer.writeUInt32BE(13, 8)
  buffer.write("IHDR", 12)
  buffer.writeUInt32BE(width, 16)
  buffer.writeUInt32BE(height, 20)
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength)
}

test("small images satisfy each purpose without cropping; large sources have two comparison modes", () => {
  const { planSourceSize } = loadNormalizer()
  for (const [minimumWidth, minimumHeight] of [[1024, 1024], [1200, 630]]) {
    for (const [width, height] of [[320, 180], [180, 320], [100, 100], [1421, 800]]) {
      const actual = planSourceSize({ width, height, minimumWidth, minimumHeight })
      const scale = Math.max(1, minimumWidth / width, minimumHeight / height)
      assert.equal(actual.scale, scale)
      assert.ok(actual.width >= minimumWidth && actual.height >= minimumHeight)
      assert.ok(Math.abs(actual.width - width * scale) <= 1)
      assert.ok(Math.abs(actual.height - height * scale) <= 1)
    }
  }
  const input = { width: 6000, height: 4000, minimumWidth: 1200, minimumHeight: 630 }
  const bounded = planSourceSize(input)
  assert.ok(bounded.reduced && bounded.width <= 4096 && bounded.width * bounded.height <= 8_000_000)
  const retained = planSourceSize({ ...input, mode: "retain" })
  assert.equal(retained.width, 6000)
  assert.equal(retained.height, 4000)
})

test("rejects unsafe, extreme and incompatible dimensions before canvas creation", () => {
  const { planSourceSize } = loadNormalizer()
  for (const [width, height] of [[0, 10], [NaN, 10], [10.5, 20], [8193, 3000], [6000, 6000], [1000, 10]]) {
    assert.throws(() => planSourceSize({ width, height, minimumWidth: 1024, minimumHeight: 1024 }))
  }
  assert.throws(() => planSourceSize({ width: 100, height: 800, minimumWidth: 1200, minimumHeight: 630, mode: "retain" }), /両立/)
  assert.throws(() => planSourceSize({ width: 800, height: 100, minimumWidth: 1024, minimumHeight: 1024 }), /両立/)
  assert.throws(() => planSourceSize({ width: 100, height: 100, minimumWidth: 1024, minimumHeight: 1024, mode: "invalid" }), /設定/)
})

test("PNG, JPEG SOF and all WebP header variants are recognized; corrupt headers are rejected", () => {
  const { inspectImageHeader } = loadNormalizer()
  assert.equal(inspectImageHeader(pngHeader(320, 180)).mimeType, "image/png")
  const jpeg = new Uint8Array([255, 216, 255, 224, 0, 2, 255, 194, 0, 8, 8, 0, 180, 1, 64, 1])
  assert.equal(inspectImageHeader(jpeg.buffer).width, 320)
  for (const type of ["VP8X", "VP8 ", "VP8L"]) {
    const buffer = Buffer.alloc(32)
    buffer.write("RIFF", 0)
    buffer.write("WEBP", 8)
    buffer.write(type, 12)
    if (type === "VP8X") { buffer.writeUIntLE(319, 24, 3); buffer.writeUIntLE(179, 27, 3) }
    if (type === "VP8 ") { Buffer.from([157, 1, 42]).copy(buffer, 23); buffer.writeUInt16LE(320, 26); buffer.writeUInt16LE(180, 28) }
    if (type === "VP8L") { buffer[20] = 47; buffer.writeUInt32LE(319 + (179 << 14), 21) }
    const header = inspectImageHeader(buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength))
    assert.equal(header.width, 320)
    assert.equal(header.height, 180)
  }
  for (const buffer of [new ArrayBuffer(0), new Uint8Array([255, 216, 255, 224, 255, 255]).buffer, new TextEncoder().encode("not a jpg").buffer]) {
    assert.throws(() => inspectImageHeader(buffer), /画像実体/)
  }
})

test("oversized byte/pixel inputs are rejected without decoding", async () => {
  let decodeCount = 0
  const { normalizeEditingSource } = loadNormalizer({ createImageBitmap: () => { decodeCount += 1 } })
  const config = { minimumWidth: 1024, minimumHeight: 1024 }
  await assert.rejects(normalizeEditingSource({ size: 21 * 1024 ** 2 }, config), /20MiB/)
  await assert.rejects(normalizeEditingSource({ size: 33, arrayBuffer: async () => pngHeader(6000, 6000) }, config), /3200万画素/)
  assert.equal(decodeCount, 0)
})

test("failed canvas allocation, null JPEG, and cancelled decoding close the bitmap", async () => {
  for (const failure of ["context", "blob", "cancel"]) {
    let closed = 0
    let current = true
    const canvas = { getContext: () => failure === "context" ? null : { fillRect() {}, drawImage() {} }, toBlob: (callback) => callback(null) }
    const { normalizeEditingSource } = loadNormalizer({
      createImageBitmap: async () => {
        if (failure === "cancel") current = false
        return { width: 320, height: 180, close: () => { closed += 1 } }
      },
      document: { createElement: () => canvas },
    })
    const file = { size: 33, type: "image/png", arrayBuffer: async () => pngHeader(320, 180) }
    await assert.rejects(normalizeEditingSource(file, { minimumWidth: 1200, minimumHeight: 630, isCurrent: () => current }), /確保|生成|中止/)
    assert.equal(closed, 1)
    if (failure !== "cancel") assert.equal(canvas.width, 0)
  }
})

test("decoder uses the inspected MIME and EXIF fallback releases its object URL", async () => {
  const revoked = []
  let cleared = false
  let decodedType
  const { normalizeEditingSource } = loadNormalizer({
    createImageBitmap: async (blob) => { decodedType = blob.type; throw new DOMException("decode", "InvalidStateError") },
    Image: class {
      naturalWidth = 320
      naturalHeight = 180
      async decode() {}
      removeAttribute() { cleared = true }
    },
    URL: { createObjectURL: () => "blob:fallback", revokeObjectURL: (url) => revoked.push(url) },
    document: { createElement: () => ({
      getContext: () => ({ fillRect() {}, drawImage() {} }),
      toBlob: (callback) => callback({ type: "image/jpeg", size: 1000 }),
    }) },
  })
  const file = { size: 33, type: "wrong/type", arrayBuffer: async () => pngHeader(320, 180), slice: (_start, _end, type) => ({ type }) }
  const result = await normalizeEditingSource(file, { minimumWidth: 1200, minimumHeight: 630 })
  assert.equal(decodedType, "image/png")
  assert.equal(result.report.decoded.method, "HTMLImageElement")
  assert.equal(cleared, true)
  assert.deepEqual(revoked, ["blob:fallback"])
})

test("animated images are explicitly excluded from this verification", () => {
  const { inspectImageHeader } = loadNormalizer()
  const png = Buffer.concat([Buffer.from(pngHeader(320, 180)), Buffer.alloc(20)])
  png.writeUInt32BE(8, 33)
  png.write("acTL", 37)
  const webp = Buffer.alloc(30)
  webp.write("RIFF", 0)
  webp.write("WEBP", 8)
  webp.write("VP8X", 12)
  webp[20] = 2
  for (const buffer of [png, webp]) {
    assert.throws(() => inspectImageHeader(buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength)), /アニメーション/)
  }
})
