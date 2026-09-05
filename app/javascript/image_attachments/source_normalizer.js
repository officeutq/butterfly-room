export const IMAGE_SOURCE_LIMITS = Object.freeze({
  bytes: 20 * 1024 ** 2,
  pixels: 32_000_000,
  edge: 8192,
  aspect: 8,
  outputPixels: 8_000_000,
  outputEdge: 4096,
  quality: 0.94,
})

export const IMAGE_SOURCE_PURPOSES = Object.freeze({
  square: Object.freeze({ minimumWidth: 1024, minimumHeight: 1024 }),
  social: Object.freeze({ minimumWidth: 1200, minimumHeight: 630 }),
})

export class ImageSourceNormalizationError extends Error {
  constructor(code, message, { cause } = {}) {
    super(message, { cause })
    this.name = "ImageSourceNormalizationError"
    this.code = code
  }
}

export function validateImageSourceDimensions(width, height) {
  if (![width, height].every((value) => Number.isSafeInteger(value) && value > 0)) {
    throw normalizationError("dimensions_unreadable", "画像の寸法を読み取れません。")
  }
  if (
    Math.max(width, height) > IMAGE_SOURCE_LIMITS.edge ||
    width * height > IMAGE_SOURCE_LIMITS.pixels
  ) {
    throw normalizationError(
      "dimensions_too_large",
      "入力画像は長辺8192px・3200万画素以下にしてください。"
    )
  }
  if (Math.max(width / height, height / width) > IMAGE_SOURCE_LIMITS.aspect) {
    throw normalizationError("aspect_ratio_too_large", "縦横比が8:1以内の画像を選択してください。")
  }
}

// Reads encoded dimensions before allocating decoded pixels. Browser decoding
// and the Rails validator still inspect the complete image independently.
export function inspectImageSourceHeader(buffer) {
  const bytes = new Uint8Array(buffer)
  const view = new DataView(buffer)
  const text = (offset, length) => String.fromCharCode(...bytes.subarray(offset, offset + length))
  const result = (width, height, mimeType) => {
    validateImageSourceDimensions(width, height)
    return { width, height, mimeType }
  }

  if (bytes.length >= 33 && text(0, 8) === "\x89PNG\r\n\x1a\n" && text(12, 4) === "IHDR") {
    for (let offset = 8; offset + 12 <= bytes.length;) {
      const length = view.getUint32(offset)
      if (offset + 12 + length > bytes.length) break
      const type = text(offset + 4, 4)
      if (type === "acTL") {
        throw normalizationError("animated_image", "アニメーションPNGは扱えません。静止画像を選択してください。")
      }
      if (type === "IDAT") break
      offset += 12 + length
    }
    return result(view.getUint32(16), view.getUint32(20), "image/png")
  }

  if (bytes[0] === 0xff && bytes[1] === 0xd8) {
    let offset = 2
    while (offset + 4 <= bytes.length && bytes[offset] === 0xff) {
      while (bytes[offset] === 0xff) offset += 1
      const marker = bytes[offset++]
      if (marker === 0xda || marker === 0xd9 || offset + 2 > bytes.length) break
      const length = view.getUint16(offset)
      if (length < 2 || offset + length > bytes.length) break
      if ([0xc0, 0xc1, 0xc2].includes(marker) && length >= 8) {
        return result(view.getUint16(offset + 5), view.getUint16(offset + 3), "image/jpeg")
      }
      offset += length
    }
  }

  if (bytes.length >= 30 && text(0, 4) === "RIFF" && text(8, 4) === "WEBP") {
    const type = text(12, 4)
    const uint24 = (offset) => bytes[offset] + (bytes[offset + 1] << 8) + (bytes[offset + 2] << 16)
    if (type === "VP8X") {
      if (bytes[20] & 2) {
        throw normalizationError("animated_image", "アニメーションWebPは扱えません。静止画像を選択してください。")
      }
      return result(uint24(24) + 1, uint24(27) + 1, "image/webp")
    }
    if (type === "VP8 " && text(23, 3) === "\x9d\x01\x2a") {
      return result(view.getUint16(26, true) & 0x3fff, view.getUint16(28, true) & 0x3fff, "image/webp")
    }
    if (type === "VP8L" && bytes[20] === 0x2f) {
      const bits = view.getUint32(21, true)
      return result((bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1, "image/webp")
    }
  }

  throw normalizationError(
    "unsupported_image",
    "画像実体を確認できません。静止画のJPEG / PNG / WebPを選択してください。"
  )
}

export function planEditingSourceSize({ width, height, ratioKey }) {
  validateImageSourceDimensions(width, height)
  const purpose = IMAGE_SOURCE_PURPOSES[ratioKey]
  if (!purpose) throw normalizationError("invalid_purpose", "画像用途の設定が不正です。")

  const requiredScale = Math.max(
    purpose.minimumWidth / width,
    purpose.minimumHeight / height
  )
  const maximumScale = Math.min(
    IMAGE_SOURCE_LIMITS.outputEdge / width,
    IMAGE_SOURCE_LIMITS.outputEdge / height,
    Math.sqrt(IMAGE_SOURCE_LIMITS.outputPixels / (width * height))
  )
  if (requiredScale > maximumScale) {
    throw normalizationError(
      "incompatible_dimensions",
      "用途の最低寸法と編集元画像の上限を両立できません。縦横比が極端でない画像を選択してください。"
    )
  }

  const scale = Math.min(Math.max(1, requiredScale), maximumScale)
  const outputWidth = Math.max(purpose.minimumWidth, Math.floor(width * scale))
  const outputHeight = Math.max(purpose.minimumHeight, Math.floor(height * scale))
  if (
    Math.max(outputWidth, outputHeight) > IMAGE_SOURCE_LIMITS.outputEdge ||
    outputWidth * outputHeight > IMAGE_SOURCE_LIMITS.outputPixels
  ) {
    throw normalizationError("output_too_large", "編集元画像の寸法が処理上限を超えます。別の画像を選択してください。")
  }

  return {
    width: outputWidth,
    height: outputHeight,
    scale,
    enlarged: scale > 1,
    reduced: scale < 1,
  }
}

export class ImageSourceNormalizer {
  constructor() {
    this.generation = 0
    this.queue = Promise.resolve()
    this.abortController = null
  }

  async normalize(file, { ratioKey }) {
    const generation = this.generation + 1
    this.generation = generation
    this.abortController?.abort()
    const abortController = new AbortController()
    this.abortController = abortController
    const previous = this.queue
    const isCurrent = () => generation === this.generation
    const operation = (async () => {
      await previous
      ensureCurrent(abortController.signal, isCurrent)
      return normalizeEditingSource(file, {
        ratioKey,
        signal: abortController.signal,
        isCurrent,
      })
    })()
    this.queue = operation.then(() => undefined, () => undefined)

    try {
      return await operation
    } finally {
      if (this.abortController === abortController) this.abortController = null
    }
  }

  cancel() {
    this.generation += 1
    this.abortController?.abort()
    this.abortController = null
  }

  dispose() {
    this.cancel()
  }
}

async function normalizeEditingSource(file, { ratioKey, signal, isCurrent }) {
  ensureCurrent(signal, isCurrent)
  if (!file?.size) throw normalizationError("empty_file", "空の画像ファイルは扱えません。")
  if (file.size > IMAGE_SOURCE_LIMITS.bytes) {
    throw normalizationError("file_too_large", "入力画像は20MiB以下にしてください。")
  }

  const header = inspectImageSourceHeader(await file.arrayBuffer())
  ensureCurrent(signal, isCurrent)
  let decoded
  let canvas
  try {
    const inputBlob = file.type === header.mimeType
      ? file
      : file.slice(0, file.size, header.mimeType)
    decoded = await decodeSource(inputBlob)
    ensureCurrent(signal, isCurrent)
    validateImageSourceDimensions(decoded.width, decoded.height)
    if (!(
      (decoded.width === header.width && decoded.height === header.height) ||
      (decoded.width === header.height && decoded.height === header.width)
    )) {
      throw normalizationError("dimension_mismatch", "画像ヘッダーと向き補正後の寸法が一致しません。")
    }

    const plan = planEditingSourceSize({
      width: decoded.width,
      height: decoded.height,
      ratioKey,
    })
    canvas = document.createElement("canvas")
    canvas.width = plan.width
    canvas.height = plan.height
    const context = canvas.getContext("2d", { colorSpace: "srgb" })
    if (!context) {
      throw normalizationError("canvas_unavailable", "描画領域を確保できません。画像を小さくして再試行してください。")
    }

    context.fillStyle = "#ffffff"
    context.fillRect(0, 0, canvas.width, canvas.height)
    context.imageSmoothingEnabled = true
    context.imageSmoothingQuality = "high"
    context.drawImage(decoded.image, 0, 0, canvas.width, canvas.height)
    const blob = await encodeJpeg(canvas)
    ensureCurrent(signal, isCurrent)
    const sourceFile = new File([blob], "source.jpg", { type: "image/jpeg" })

    return {
      file: sourceFile,
      input: {
        name: file.name,
        mimeType: header.mimeType,
        bytes: file.size,
        encodedWidth: header.width,
        encodedHeight: header.height,
      },
      decoded: {
        width: decoded.width,
        height: decoded.height,
        orientation: "from-image",
        method: decoded.method,
      },
      source: {
        ...plan,
        mimeType: sourceFile.type,
        bytes: sourceFile.size,
        quality: IMAGE_SOURCE_LIMITS.quality,
        colorSpace: context.getContextAttributes?.().colorSpace || "srgb",
        background: "white",
      },
      warning: warningFor(plan),
    }
  } catch (error) {
    if (error instanceof ImageSourceNormalizationError) throw error

    throw normalizationError(
      "decode_failed",
      "画像のデコード・変換に失敗しました。破損していない小さい画像で再試行してください。",
      error
    )
  } finally {
    decoded?.close()
    if (canvas) {
      canvas.width = 0
      canvas.height = 0
    }
  }
}

function encodeJpeg(canvas) {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob?.type === "image/jpeg" && blob.size > 0) {
        resolve(blob)
      } else {
        reject(normalizationError(
          "encode_failed",
          "編集元JPEGを生成できません。画像を小さくして再試行してください。"
        ))
      }
    }, "image/jpeg", IMAGE_SOURCE_LIMITS.quality)
  })
}

async function decodeSource(blob) {
  if (typeof createImageBitmap === "function") {
    try {
      const image = await createImageBitmap(blob, {
        imageOrientation: "from-image",
        colorSpaceConversion: "default",
      })
      return {
        image,
        width: image.width,
        height: image.height,
        method: "createImageBitmap",
        close: () => image.close(),
      }
    } catch (error) {
      // Firefox can reject an EXIF JPEG that HTMLImageElement decodes correctly.
      // Do not retry allocation failures through a second decoder.
      if (error.name !== "InvalidStateError") throw error
    }
  }

  const image = new Image()
  const url = URL.createObjectURL(blob)
  const close = () => {
    image.removeAttribute("src")
    URL.revokeObjectURL(url)
  }
  try {
    image.src = url
    await image.decode()
    return {
      image,
      width: image.naturalWidth,
      height: image.naturalHeight,
      method: "HTMLImageElement",
      close,
    }
  } catch (error) {
    close()
    throw error
  }
}

function warningFor(plan) {
  if (plan.enlarged) {
    return {
      code: "source_enlarged",
      message: `小さい画像を約${round(plan.scale, 2)}倍に拡大しました。保存できますが、細部の解像感は増えません。`,
    }
  }
  if (plan.reduced) {
    return {
      code: "source_reduced",
      message: "大きい画像を長辺4096px・800万画素の上限内へ縮小しました。",
    }
  }

  return null
}

function ensureCurrent(signal, isCurrent) {
  if (!signal.aborted && isCurrent()) return

  throw normalizationError("aborted", "画像の変換を中止しました。")
}

function normalizationError(code, message, cause) {
  return new ImageSourceNormalizationError(code, message, { cause })
}

function round(value, precision) {
  const multiplier = 10 ** precision
  return Math.round(value * multiplier) / multiplier
}
