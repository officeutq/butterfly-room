// Verification-only adapter for the unmodified CSP build shipped by heic-to 1.5.2.
// See docs/design/heic_verification.md for version, license, and limitations.
export const HEIC_LIMITS = Object.freeze({ bytes: 20 * 1024 ** 2, pixels: 16_000_000, comparisonPixels: 32_000_000, edge: 8192, images: 20, mainPixels: 4_000_000 })

function pixelLimitFor(mode, limitMode) {
  if (!["worker", "main"].includes(mode)) throw new Error("HEIC変換方式が不正です。")
  if (!["standard", "large"].includes(limitMode)) throw new Error("HEICの上限設定が不正です。")
  if (mode === "main") return HEIC_LIMITS.mainPixels
  return limitMode === "large" ? HEIC_LIMITS.comparisonPixels : HEIC_LIMITS.pixels
}

export function validateHeicDimensions(width, height, mode, limitMode = "standard") {
  const pixels = pixelLimitFor(mode, limitMode)
  if (![width, height].every((value) => Number.isSafeInteger(value) && value > 0) ||
      width * height > pixels || Math.max(width, height) > HEIC_LIMITS.edge || Math.max(width / height, height / width) > 8) {
    throw new Error(mode === "main"
      ? "メインスレッド比較は400万画素以下です。Worker方式で試してください。"
      : `HEIC / HEIF（${width}×${height}px）が暫定上限（${pixels / 10_000}万画素・長辺8192px・縦横比8:1）を超えています。`)
  }
}

export async function convertHeicBuffer({ buffer, decoderUrl, mode = "worker", limitMode = "standard", signal }) {
  const started = performance.now()
  const check = () => { if (signal?.aborted) throw new DOMException("変換を中止しました。", "AbortError") }
  check()
  const pixelLimit = pixelLimitFor(mode, limitMode)
  const effectiveLimitMode = mode === "main" ? "standard" : limitMode
  if (!(buffer instanceof ArrayBuffer) || !buffer.byteLength || buffer.byteLength > HEIC_LIMITS.bytes) {
    throw new Error("HEIC / HEIFは空でない20MiB以下のファイルを選択してください。")
  }
  const { default: buildLibheif } = await import(decoderUrl)
  check()
  const lib = buildLibheif({ print() {}, printErr() {} })
  const loadedAt = performance.now()
  let decoder
  let images = []
  let decoded
  let canvas
  try {
    decoder = new lib.HeifDecoder()
    images = decoder.decode(new Uint8Array(buffer))
    if (!images.length || images.length > HEIC_LIMITS.images) throw new Error("HEIC / HEIFの静止画像を確認できません（最大20画像）。")
    const first = images[0]
    const width = first.get_width()
    const height = first.get_height()
    // Check dimensions before decompressing pixels, and decode only the first image.
    validateHeicDimensions(width, height, mode, effectiveLimitMode)
    check()
    decoded = await lib.heif_js_decode_image2(first.handle, lib.heif_colorspace.heif_colorspace_RGB, lib.heif_chroma.heif_chroma_interleaved_RGBA)
    if (!decoded || decoded.code) throw new Error("対応外または破損したHEIC / HEIFです。JPEGへ書き出して再試行してください。")
    const channel = decoded.channels?.find((item) => item.id === lib.heif_channel.heif_channel_interleaved)
    if (!channel || channel.width !== width || channel.height !== height ||
        !Number.isSafeInteger(channel.stride) || channel.stride < width * 4 ||
        !(channel.data instanceof Uint8Array) || channel.data.byteLength < channel.stride * height) {
      throw new Error("HEIC / HEIFの画像寸法・画素データを確認できません。")
    }
    const rgba = new Uint8ClampedArray(width * height * 4)
    for (let y = 0; y < height; y += 1) {
      rgba.set(channel.data.slice(y * channel.stride, y * channel.stride + width * 4), y * width * 4)
    }
    check()
    if (typeof OffscreenCanvas !== "function" && typeof document === "undefined") {
      const ended = performance.now()
      return { rgbaBuffer: rgba.buffer, report: {
        library: "heic-to 1.5.2 / bundled libheif 1.22.2 (CSP build)", mode, limitMode: effectiveLimitMode, pixelLimit,
        imageCount: images.length, selectedImageIndex: 0, width, height, bytes: null, quality: 0.94,
        memory: { rgbaBytes: rgba.byteLength, libraryHeapBytes: lib.HEAPU8?.byteLength ?? null, peakBytes: null },
        milliseconds: { libraryLoad: loadedAt - started, decodeAndDraw: ended - loadedAt, encode: 0, total: ended - started },
      } }
    }
    canvas = typeof OffscreenCanvas === "function" ? new OffscreenCanvas(width, height) : document.createElement("canvas")
    canvas.width = width
    canvas.height = height
    const context = canvas.getContext("2d", { colorSpace: "srgb" })
    if (!context) throw new Error("HEIC変換の描画領域を確保できません。小さい画像で試してください。")
    context.putImageData(new ImageData(rgba, width, height), 0, 0)
    context.globalCompositeOperation = "destination-over"
    context.fillStyle = "#ffffff"
    context.fillRect(0, 0, width, height)
    const heapBytes = lib.HEAPU8?.byteLength ?? null
    lib.heif_image_release(decoded.image)
    decoded = null
    const decodedAt = performance.now()
    const blob = typeof canvas.convertToBlob === "function"
      ? await canvas.convertToBlob({ type: "image/jpeg", quality: 0.94 })
      : await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.94))
    check()
    if (blob?.type !== "image/jpeg" || !blob.size) throw new Error("HEIC / HEIFからJPEGを生成できませんでした。")
    const ms = (value) => Math.round(value * 10) / 10
    return { blob, report: {
      library: "heic-to 1.5.2 / bundled libheif 1.22.2 (CSP build)", mode, limitMode: effectiveLimitMode, pixelLimit,
      jpegEncoder: typeof OffscreenCanvas === "function" ? "offscreen-canvas" : "main-canvas",
      imageCount: images.length, selectedImageIndex: 0, width, height, bytes: blob.size, quality: 0.94,
      memory: { rgbaBytes: rgba.byteLength, libraryHeapBytes: heapBytes, peakBytes: null },
      milliseconds: { libraryLoad: ms(loadedAt - started), decodeAndDraw: ms(decodedAt - loadedAt), encode: ms(performance.now() - decodedAt), total: ms(performance.now() - started) },
    } }
  } finally {
    if (decoded?.image) lib.heif_image_release(decoded.image)
    images.forEach((image) => image.free())
    if (decoder?.decoder) lib.heif_context_free(decoder.decoder)
    if (canvas) { canvas.width = 0; canvas.height = 0 }
  }
}

// Worker decoding remains mandatory when selected; only JPEG encoding moves to
// the page on engines without OffscreenCanvas in workers (e.g. Windows WebKit).
export async function encodeHeicRgba({ rgbaBuffer, report }, { limitMode = "standard" } = {}) {
  const started = performance.now()
  const { width, height } = report
  validateHeicDimensions(width, height, "worker", limitMode)
  if (rgbaBuffer.byteLength !== width * height * 4) throw new Error("変換済みHEICの画素データが不正です。")
  const canvas = document.createElement("canvas")
  try {
    canvas.width = width
    canvas.height = height
    const context = canvas.getContext("2d", { colorSpace: "srgb" })
    if (!context) throw new Error("JPEGの描画領域を確保できません。")
    context.putImageData(new ImageData(new Uint8ClampedArray(rgbaBuffer), width, height), 0, 0)
    context.globalCompositeOperation = "destination-over"
    context.fillStyle = "#ffffff"
    context.fillRect(0, 0, width, height)
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.94))
    if (blob?.type !== "image/jpeg" || !blob.size) throw new Error("HEIC / HEIFからJPEGを生成できませんでした。")
    const duration = Math.round((performance.now() - started) * 10) / 10
    return { blob, report: { ...report, bytes: blob.size, jpegEncoder: "main-canvas", milliseconds: { ...report.milliseconds, encode: duration, total: report.milliseconds.total + duration } } }
  } finally { canvas.width = 0; canvas.height = 0 }
}

if (typeof WorkerGlobalScope !== "undefined" && globalThis instanceof WorkerGlobalScope) {
  self.onmessage = async (event) => {
    try {
      const result = await convertHeicBuffer(event.data)
      self.postMessage({ ok: true, ...result }, result.rgbaBuffer ? [result.rgbaBuffer] : [])
    } catch (error) {
      self.postMessage({ ok: false, error: error.message || "HEIC / HEIF変換に失敗しました。" })
    }
  }
}
