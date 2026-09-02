// Verification-only candidates. These are not production upload limits.
export const SOURCE_LIMITS = Object.freeze({
  bytes: 20 * 1024 ** 2,
  pixels: 32_000_000,
  edge: 8192,
  aspect: 8,
})
const OUTPUT_LIMITS = Object.freeze({
  bounded: { pixels: 8_000_000, edge: 4096 },
  retain: { pixels: SOURCE_LIMITS.pixels, edge: SOURCE_LIMITS.edge },
})

export function validateSourceDimensions(width, height) {
  if (![width, height].every((value) => Number.isSafeInteger(value) && value > 0)) {
    throw new Error("画像の寸法を読み取れません。")
  }
  if (Math.max(width, height) > SOURCE_LIMITS.edge || width * height > SOURCE_LIMITS.pixels) {
    throw new Error("入力画像が暫定上限（長辺8192px・3200万画素）を超えています。小さい画像で試してください。")
  }
  if (Math.max(width / height, height / width) > SOURCE_LIMITS.aspect) {
    throw new Error("縦横比が暫定上限の8:1を超えています。別の画像で試してください。")
  }
}

// Read dimensions before allocating decoded pixels. This is a bounded header
// check, not a replacement for browser decoding or future server validation.
export function inspectImageHeader(buffer) {
  const bytes = new Uint8Array(buffer)
  const view = new DataView(buffer)
  const text = (offset, length) => String.fromCharCode(...bytes.subarray(offset, offset + length))
  const result = (width, height, mimeType) => {
    validateSourceDimensions(width, height)
    return { width, height, mimeType }
  }
  if (bytes.length >= 33 && text(0, 8) === "\x89PNG\r\n\x1a\n" && text(12, 4) === "IHDR") {
    for (let offset = 8; offset + 12 <= bytes.length;) {
      const length = view.getUint32(offset)
      if (offset + 12 + length > bytes.length) break
      const type = text(offset + 4, 4)
      if (type === "acTL") throw new Error("アニメーションPNGは今回の検証対象外です。静止画像で試してください。")
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
      if (bytes[20] & 2) throw new Error("アニメーションWebPは今回の検証対象外です。静止画像で試してください。")
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
  throw new Error("画像実体を確認できません。静止画のJPEG / PNG / WebPを選択してください。")
}

export function planSourceSize({ width, height, minimumWidth, minimumHeight, mode = "bounded" }) {
  validateSourceDimensions(width, height)
  const limits = OUTPUT_LIMITS[mode]
  if (!limits || ![minimumWidth, minimumHeight].every((value) => Number.isSafeInteger(value) && value > 0)) {
    throw new Error("正規化の設定が不正です。")
  }
  const requiredScale = Math.max(minimumWidth / width, minimumHeight / height)
  const maximumScale = Math.min(limits.edge / width, limits.edge / height, Math.sqrt(limits.pixels / (width * height)))
  if (requiredScale > maximumScale) {
    throw new Error("用途の最低寸法と編集元の暫定上限を両立できません。縦横比が極端でない画像、または別の比較設定で試してください。")
  }
  const scale = Math.min(Math.max(1, requiredScale), maximumScale)
  // Round down for the upper bound, but never undershoot the required dimension.
  const outputWidth = Math.max(minimumWidth, Math.floor(width * scale))
  const outputHeight = Math.max(minimumHeight, Math.floor(height * scale))
  if (Math.max(outputWidth, outputHeight) > limits.edge || outputWidth * outputHeight > limits.pixels) {
    throw new Error("編集元画像の寸法が暫定上限を超えます。別の画像で試してください。")
  }
  return { width: outputWidth, height: outputHeight, scale, enlarged: scale > 1, reduced: scale < 1 }
}

function encodeJpeg(canvas, quality) {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob?.type === "image/jpeg" && blob.size > 0) resolve(blob)
      else reject(new Error("編集元JPEGを生成できません。画像を小さくして再試行してください。"))
    }, "image/jpeg", quality)
  })
}

async function decodeSource(blob) {
  if (typeof createImageBitmap === "function") {
    try {
      const image = await createImageBitmap(blob, { imageOrientation: "from-image", colorSpaceConversion: "default" })
      return { image, width: image.width, height: image.height, method: "createImageBitmap", close: () => image.close() }
    } catch (error) {
      // Firefox can reject an EXIF JPEG that HTMLImageElement decodes correctly.
      // Do not retry allocation failures through a second decoder.
      if (error.name !== "InvalidStateError") throw error
    }
  }
  const image = new Image()
  const url = URL.createObjectURL(blob)
  const close = () => { image.removeAttribute("src"); URL.revokeObjectURL(url) }
  try {
    image.src = url
    await image.decode()
    return { image, width: image.naturalWidth, height: image.naturalHeight, method: "HTMLImageElement", close }
  } catch (error) {
    close()
    throw error
  }
}

export async function normalizeEditingSource(file, {
  minimumWidth, minimumHeight, quality = 0.94, mode = "bounded", isCurrent = () => true,
}) {
  const started = performance.now()
  const checkCurrent = () => {
    if (!isCurrent()) throw new DOMException("画像の変換を中止しました。", "AbortError")
  }
  checkCurrent()
  if (!file.size || file.size > SOURCE_LIMITS.bytes) {
    throw new Error("空のファイル、または暫定上限20MiBを超える画像は扱えません。")
  }
  if (![0.9, 0.94, 0.98].includes(quality)) throw new Error("JPEG品質の設定が不正です。")
  const header = inspectImageHeader(await file.arrayBuffer())
  checkCurrent()
  let bitmap
  let canvas
  try {
    // Decode once with EXIF orientation; do not apply an additional rotation.
    const inputBlob = file.type === header.mimeType ? file : file.slice(0, file.size, header.mimeType)
    bitmap = await decodeSource(inputBlob)
    checkCurrent()
    const decodedAt = performance.now()
    validateSourceDimensions(bitmap.width, bitmap.height)
    if (!((bitmap.width === header.width && bitmap.height === header.height) ||
          (bitmap.width === header.height && bitmap.height === header.width))) {
      throw new Error("画像ヘッダーとデコード後の寸法が一致しません。")
    }
    const plan = planSourceSize({ width: bitmap.width, height: bitmap.height, minimumWidth, minimumHeight, mode })
    canvas = document.createElement("canvas")
    canvas.width = plan.width
    canvas.height = plan.height
    const context = canvas.getContext("2d", { colorSpace: "srgb" })
    if (!context) throw new Error("描画領域を確保できません。画像を小さくして再試行してください。")
    context.fillStyle = "#ffffff"
    context.fillRect(0, 0, canvas.width, canvas.height)
    context.imageSmoothingEnabled = true
    context.imageSmoothingQuality = "high"
    context.drawImage(bitmap.image, 0, 0, canvas.width, canvas.height)
    const drawnAt = performance.now()
    const blob = await encodeJpeg(canvas, quality)
    checkCurrent()
    const ended = performance.now()
    const ms = (value) => Math.round(value * 10) / 10
    return {
      blob,
      report: {
        input: { name: file.name, mimeType: header.mimeType, bytes: file.size, encodedWidth: header.width, encodedHeight: header.height },
        decoded: { width: bitmap.width, height: bitmap.height, orientation: "from-image", method: bitmap.method },
        source: { ...plan, mimeType: blob.type, bytes: blob.size, quality, colorSpace: context.getContextAttributes?.().colorSpace || "srgb", background: "white" },
        mode,
        milliseconds: { decodeAndInspect: ms(decodedAt - started), draw: ms(drawnAt - decodedAt), encode: ms(ended - drawnAt), total: ms(ended - started) },
        userAgent: navigator.userAgent,
      },
    }
  } catch (error) {
    if (error.name === "InvalidStateError" || error.name === "EncodingError" || error.name === "RangeError") {
      throw new Error("画像のデコード・変換に失敗しました。破損していない小さい画像で再試行してください。", { cause: error })
    }
    throw error
  } finally {
    bitmap?.close()
    if (canvas) { canvas.width = 0; canvas.height = 0 }
  }
}
