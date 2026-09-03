const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")

const moduleUrl = (source) => `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const load = (file) => import(moduleUrl(fs.readFileSync(path.resolve(__dirname, "../../app/javascript", file), "utf8")))
const converter = load("controllers/image_upload_verification/heic_converter.js")
const worker = load("image_upload_verification/heic_worker.js")

function header(major, compatible = []) {
  const buffer = new ArrayBuffer(16 + compatible.length * 4)
  const bytes = new Uint8Array(buffer)
  new DataView(buffer).setUint32(0, buffer.byteLength)
  bytes.set(Buffer.from(`ftyp${major}`), 4)
  compatible.forEach((brand, index) => bytes.set(Buffer.from(brand), 16 + index * 4))
  return buffer
}

test("HEIF detection checks ftyp boundaries and compatible brands, not extension alone", async () => {
  const { heifBrand, isHeicNamed } = await converter
  for (const brand of ["heic", "heix", "hevc", "hevx", "mif1", "msf1"]) assert.equal(heifBrand(header(brand)), brand)
  assert.equal(heifBrand(header("xxxx", ["heic"])), "heic")
  for (const buffer of [new ArrayBuffer(0), header("avif", ["mif1"]), header("mif1", ["avis"]), header("xxxx")]) assert.equal(heifBrand(buffer), null)
  for (const length of [0, 1, 15, 17, 1000]) {
    const buffer = header("heic")
    new DataView(buffer).setUint32(0, length)
    assert.equal(heifBrand(buffer), null)
  }
  assert.equal(isHeicNamed({ name: "photo.HEIF", type: "" }), true)
  assert.equal(isHeicNamed({ name: "photo", type: "image/heic-sequence" }), true)
  assert.equal(isHeicNamed({ name: "photo.jpg", type: "image/jpeg" }), false)
})

test("ordinary files are passed through; empty, oversized, mislabeled and aborted files are rejected", async () => {
  const { prepareHeicInput } = await converter
  const options = { workerUrl: "unused", decoderUrl: "unused" }
  const jpeg = new File(["jpeg fixture"], "photo.jpg", { type: "image/jpeg" })
  assert.equal((await prepareHeicInput(jpeg, options)).file, jpeg)
  for (const file of [new File([], "empty.heic"), new File(["bad"], "bad.heic"), { size: 20 * 1024 ** 2 + 1 }]) {
    await assert.rejects(prepareHeicInput(file, options))
  }
  await assert.rejects(prepareHeicInput(jpeg, { ...options, signal: AbortSignal.abort() }), { name: "AbortError" })
  await assert.rejects(prepareHeicInput(jpeg, { ...options, mode: "invalid" }), /方式/)
  await assert.rejects(prepareHeicInput(jpeg, { ...options, limitMode: "invalid" }), /上限設定/)
})

test("Worker is terminated on success, decode failure, worker error, transfer failure, abort and timeout", async (t) => {
  const { convertInWorker } = await converter
  const original = global.Worker
  t.after(() => { global.Worker = original })
  for (const scenario of ["success", "failure", "error", "messageerror", "throw", "abort", "timeout"]) {
    let instance
    const abort = new AbortController()
    global.Worker = class {
      constructor(url, options) { instance = this; this.terminated = 0; assert.equal(options.type, "module") }
      terminate() { this.terminated += 1 }
      postMessage(data, transfer) {
        assert.equal(data.mode, "worker")
        assert.equal(data.limitMode, "standard")
        assert.equal(transfer[0], data.buffer)
        if (scenario === "throw") throw new Error("transfer failed")
        queueMicrotask(() => {
          if (scenario === "success") this.onmessage({ data: { ok: true, blob: "jpeg" } })
          if (scenario === "failure") this.onmessage({ data: { ok: false, error: "decode failed" } })
          if (scenario === "error") this.onerror()
          if (scenario === "messageerror") this.onmessageerror()
          if (scenario === "abort") abort.abort()
        })
      }
    }
    const promise = convertInWorker(new ArrayBuffer(4), { workerUrl: "/worker", decoderUrl: "/decoder", signal: abort.signal, timeoutMs: 5 })
    if (scenario === "success") assert.equal((await promise).blob, "jpeg")
    else await assert.rejects(promise)
    assert.equal(instance.terminated, 1, scenario)
    abort.abort()
    assert.equal(instance.terminated, 1, "late abort cannot terminate twice")
  }
  let created = false
  global.Worker = class { constructor() { created = true } }
  await assert.rejects(convertInWorker(new ArrayBuffer(4), { signal: AbortSignal.abort() }), { name: "AbortError" })
  assert.equal(created, false)
})

test("HEIC dimension limits distinguish Worker and main comparison before pixel allocation", async () => {
  const { validateHeicDimensions } = await worker
  validateHeicDimensions(4000, 4000, "worker")
  validateHeicDimensions(2000, 2000, "main")
  for (const [width, height] of [[4001, 4000], [8193, 1025], [8000, 999], [0, 1], [NaN, 1], [1.5, 2]]) {
    assert.throws(() => validateHeicDimensions(width, height, "worker"))
  }
  assert.throws(() => validateHeicDimensions(2001, 2000, "main"), /400万/)
  assert.throws(() => validateHeicDimensions(100, 100, "unknown"), /方式/)
  assert.throws(() => validateHeicDimensions(5712, 4284, "worker"), /5712×4284.*1600万/)
  validateHeicDimensions(5712, 4284, "worker", "large")
  validateHeicDimensions(8000, 4000, "worker", "large")
  for (const [width, height] of [[8000, 4001], [8064, 6048], [8193, 1025], [8000, 999], [0, 1]]) {
    assert.throws(() => validateHeicDimensions(width, height, "worker", "large"), /3200万/)
  }
  assert.throws(() => validateHeicDimensions(2001, 2000, "main", "large"), /400万/)
  assert.throws(() => validateHeicDimensions(100, 100, "worker", "invalid"), /上限設定/)
})

test("HEIC comparison selection is transferred to Worker without altering pass-through images", async (t) => {
  const { prepareHeicInput } = await converter
  const original = global.Worker
  t.after(() => { global.Worker = original })
  let count = 0
  global.Worker = class {
    terminate() {}
    postMessage(data) {
      count++
      assert.equal(data.limitMode, "large")
      queueMicrotask(() => this.onmessage({ data: { ok: true, blob: new Blob(["jpeg"], { type: "image/jpeg" }), report: { limitMode: data.limitMode, pixelLimit: 32_000_000 } } }))
    }
  }
  const options = { workerUrl: "/worker", decoderUrl: "/decoder", limitMode: "large" }
  const jpeg = new File(["jpeg"], "photo.jpg", { type: "image/jpeg" })
  assert.equal((await prepareHeicInput(jpeg, options)).conversion, null)
  assert.equal(count, 0)
  const result = await prepareHeicInput(new File([header("heic")], "photo.heic"), options)
  assert.equal(result.conversion.limitMode, "large")
  assert.equal(result.conversion.pixelLimit, 32_000_000)
  assert.equal(count, 1)
})

test("RGBA fallback also enforces the explicitly chosen pixel limit", async () => {
  const { encodeHeicRgba } = await worker
  const result = { rgbaBuffer: new ArrayBuffer(0), report: { width: 5712, height: 4284, limitMode: "large" } }
  await assert.rejects(encodeHeicRgba(result), /1600万/, "report alone must not opt in to the larger allocation")
  await assert.rejects(encodeHeicRgba(result, { limitMode: "large" }), /画素データ/, "valid dimensions reach the RGBA length check")
  await assert.rejects(encodeHeicRgba(result, { limitMode: "invalid" }), /上限設定/)
})

test("native handles are freed on success, dimension rejection, decoder error and invalid channel", async () => {
  const { convertHeicBuffer } = await worker
  for (const scenario of ["success", "dimensions", "dimensions24", "decodeError", "shortChannel", "manyImages"]) {
    const source = `
      export const calls = { pixels: 0, image: 0, handle: 0, context: 0 }
      export default function build() {
        return {
          HeifDecoder: class {
            constructor() { this.decoder = 123 }
            decode() { return Array.from({ length: ${scenario === "manyImages" ? 21 : 1} }, () => ({ handle: 1,
              get_width: () => ${scenario === "dimensions" ? 9000 : scenario === "dimensions24" ? 5712 : 2}, get_height: () => ${scenario === "dimensions24" ? 4284 : 2},
              free() { calls.handle++ } })) }
          },
          heif_colorspace: { heif_colorspace_RGB: 1 }, heif_chroma: { heif_chroma_interleaved_RGBA: 1 },
          heif_channel: { heif_channel_interleaved: 1 },
          heif_js_decode_image2() {
            calls.pixels++
            return ${scenario === "decodeError" ? "{ code: 1 }" : `{ image: 2, channels: [{ id: 1, width: 2, height: 2, stride: 8, data: new Uint8Array(${scenario === "shortChannel" ? 4 : 16}) }] }`}
          },
          heif_image_release() { calls.image++ }, heif_context_free() { calls.context++ }
        }
      }`
    const decoderUrl = moduleUrl(source)
    const { calls } = await import(decoderUrl)
    const promise = convertHeicBuffer({ buffer: new ArrayBuffer(4), decoderUrl })
    if (scenario === "success") assert.equal((await promise).rgbaBuffer.byteLength, 16)
    else await assert.rejects(promise)
    assert.equal(calls.context, 1, scenario)
    assert.equal(calls.handle, scenario === "manyImages" ? 21 : 1, scenario)
    assert.equal(calls.pixels, ["dimensions", "dimensions24", "manyImages"].includes(scenario) ? 0 : 1, scenario)
    assert.equal(calls.image, ["success", "shortChannel"].includes(scenario) ? 1 : 0, scenario)
  }
  await assert.rejects(convertHeicBuffer({ buffer: new ArrayBuffer(0) }), /20MiB/)
  await assert.rejects(convertHeicBuffer({ buffer: new ArrayBuffer(1), signal: AbortSignal.abort() }), { name: "AbortError" })
  await assert.rejects(convertHeicBuffer({ buffer: new ArrayBuffer(1), limitMode: "invalid" }), /上限設定/)
})
