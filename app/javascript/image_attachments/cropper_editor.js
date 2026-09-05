export const IMAGE_CROP_SCHEMA_VERSION = 1
export const IMAGE_CROP_JPEG_QUALITY = 0.9
export const IMAGE_CROP_CONFIGS = Object.freeze({
  square: Object.freeze({ ratio: 1, width: 1024, height: 1024 }),
  social: Object.freeze({ ratio: 40 / 21, width: 1200, height: 630 }),
})

export const IMAGE_CROP_TRANSFORM_EPSILON = 1e-7
const CROP_RATIO_TOLERANCE = 1
const ZOOM_TOLERANCE = 0.001

export class ImageCropStateError extends Error {
  constructor(code, message) {
    super(message)
    this.name = "ImageCropStateError"
    this.code = code
  }
}

export function cropConfigFor(ratioKey) {
  const config = IMAGE_CROP_CONFIGS[ratioKey]
  if (!config) throw cropError("invalid_ratio", "対応していない画像用途です。")

  return config
}

export function normalizeCropToSource({ crop, sourceWidth, sourceHeight, tolerance = 0 }) {
  const values = [crop?.x, crop?.y, crop?.width, crop?.height, sourceWidth, sourceHeight, tolerance]

  if (!values.every(Number.isFinite) || crop.width <= 0 || crop.height <= 0) {
    throw cropError("invalid_crop", "クロップ座標が不正です。")
  }
  if (
    crop.width > sourceWidth + tolerance ||
    crop.height > sourceHeight + tolerance ||
    crop.x < -tolerance ||
    crop.y < -tolerance ||
    crop.x + crop.width > sourceWidth + tolerance ||
    crop.y + crop.height > sourceHeight + tolerance
  ) {
    throw cropError("crop_out_of_bounds", "クロップ範囲が編集元画像の外側です。")
  }

  const width = Math.min(crop.width, sourceWidth)
  const height = Math.min(crop.height, sourceHeight)

  return {
    x: clamp(crop.x, 0, sourceWidth - width),
    y: clamp(crop.y, 0, sourceHeight - height),
    width,
    height,
  }
}

export function cropStateFromTransform({ selection, matrix, sourceWidth, sourceHeight, ratioKey }) {
  const topLeft = inverseTransformPoint(
    selection.x,
    selection.y,
    matrix,
    sourceWidth,
    sourceHeight
  )
  const bottomRight = inverseTransformPoint(
    selection.x + selection.width,
    selection.y + selection.height,
    matrix,
    sourceWidth,
    sourceHeight
  )
  const rawCrop = {
    x: Math.min(topLeft.x, bottomRight.x),
    y: Math.min(topLeft.y, bottomRight.y),
    width: Math.abs(bottomRight.x - topLeft.x),
    height: Math.abs(bottomRight.y - topLeft.y),
  }
  const output = cropConfigFor(ratioKey)

  if (rawCrop.width <= 0 || rawCrop.height <= 0) {
    throw cropError("invalid_crop", "クロップ範囲を取得できません。")
  }

  // Cropper.js may expose less than one output pixel because of subpixel rounding.
  // Shift that tiny overflow inside the source without changing its size or ratio.
  const tolerance = Math.max(
    rawCrop.width / output.width,
    rawCrop.height / output.height,
    1
  )
  const crop = normalizeCropToSource({ crop: rawCrop, sourceWidth, sourceHeight, tolerance })

  return {
    schemaVersion: IMAGE_CROP_SCHEMA_VERSION,
    ratioKey,
    source: {
      width: sourceWidth,
      height: sourceHeight,
    },
    crop: {
      x: round(crop.x),
      y: round(crop.y),
      width: round(crop.width),
      height: round(crop.height),
    },
    zoom: round(sourceWidth / crop.width),
    output: {
      width: output.width,
      height: output.height,
      mimeType: "image/jpeg",
      quality: IMAGE_CROP_JPEG_QUALITY,
    },
  }
}

export function validateCropState({ state, ratioKey, sourceWidth, sourceHeight, sourceBlobId = null }) {
  const output = cropConfigFor(ratioKey)
  if (
    state?.schemaVersion !== IMAGE_CROP_SCHEMA_VERSION ||
    state?.ratioKey !== ratioKey ||
    state?.output?.width !== output.width ||
    state?.output?.height !== output.height ||
    state?.output?.mimeType !== "image/jpeg" ||
    state?.output?.quality !== IMAGE_CROP_JPEG_QUALITY
  ) {
    throw cropError("unsupported_state", "対応していないクロップ状態です。")
  }
  if (
    ![state?.source?.width, state?.source?.height].every((value) => Number.isSafeInteger(value) && value > 0) ||
    state.source.width !== sourceWidth ||
    state.source.height !== sourceHeight
  ) {
    throw cropError("source_mismatch", "編集元画像のサイズがクロップ情報と一致しません。")
  }
  if (sourceBlobId !== null && (
    !Number.isSafeInteger(sourceBlobId) ||
    sourceBlobId <= 0 ||
    state.sourceBlobId !== sourceBlobId
  )) {
    throw cropError("source_id_mismatch", "編集元画像がクロップ情報と一致しません。画面を読み直してください。")
  }

  const tolerance = Math.max(
    state?.crop?.width / output.width,
    state?.crop?.height / output.height,
    1
  )
  const crop = normalizeCropToSource({
    crop: state?.crop,
    sourceWidth,
    sourceHeight,
    tolerance,
  })
  if (Math.abs(crop.width * output.height - crop.height * output.width) > CROP_RATIO_TOLERANCE) {
    throw cropError("invalid_crop_ratio", "クロップ範囲の比率が画像用途と一致しません。")
  }

  const zoom = round(sourceWidth / crop.width)
  if (!Number.isFinite(state.zoom) || state.zoom <= 0 || Math.abs(state.zoom - zoom) > ZOOM_TOLERANCE) {
    throw cropError("invalid_zoom", "クロップ倍率が不正です。")
  }

  const validated = {
    schemaVersion: IMAGE_CROP_SCHEMA_VERSION,
    ratioKey,
    source: { width: sourceWidth, height: sourceHeight },
    crop,
    zoom,
    output: {
      width: output.width,
      height: output.height,
      mimeType: "image/jpeg",
      quality: IMAGE_CROP_JPEG_QUALITY,
    },
  }
  if (sourceBlobId !== null) validated.sourceBlobId = sourceBlobId

  return validated
}

export function transformFromCropState({ crop, selection, sourceWidth, sourceHeight }) {
  const scaleX = selection.width / crop.width
  const scaleY = selection.height / crop.height
  const scale = (scaleX + scaleY) / 2
  const centerX = sourceWidth / 2
  const centerY = sourceHeight / 2
  const translateX = selection.x - centerX - (scale * (crop.x - centerX))
  const translateY = selection.y - centerY - (scale * (crop.y - centerY))

  return [scale, 0, 0, scale, translateX, translateY]
}

export function selectionBoxForRatio({ canvasWidth, canvasHeight, ratio, coverage = 0.82 }) {
  const availableWidth = canvasWidth * coverage
  const availableHeight = canvasHeight * coverage
  let width = availableWidth
  let height = width / ratio

  if (height > availableHeight) {
    height = availableHeight
    width = height * ratio
  }

  return {
    x: (canvasWidth - width) / 2,
    y: (canvasHeight - height) / 2,
    width,
    height,
  }
}

export function transformedImageBounds({ matrix, sourceWidth, sourceHeight }) {
  const [a, b, c, d, e, f] = matrix
  const centerX = sourceWidth / 2
  const centerY = sourceHeight / 2
  const points = [
    [0, 0],
    [sourceWidth, 0],
    [0, sourceHeight],
    [sourceWidth, sourceHeight],
  ].map(([x, y]) => ({
    x: centerX + (a * (x - centerX)) + (c * (y - centerY)) + e,
    y: centerY + (b * (x - centerX)) + (d * (y - centerY)) + f,
  }))
  const xValues = points.map((point) => point.x)
  const yValues = points.map((point) => point.y)

  return {
    left: Math.min(...xValues),
    top: Math.min(...yValues),
    right: Math.max(...xValues),
    bottom: Math.max(...yValues),
  }
}

export function transformCoversSelection({ matrix, selection, sourceWidth, sourceHeight, tolerance = 0.5 }) {
  const bounds = transformedImageBounds({ matrix, sourceWidth, sourceHeight })

  return bounds.left <= selection.x + tolerance &&
    bounds.top <= selection.y + tolerance &&
    bounds.right >= selection.x + selection.width - tolerance &&
    bounds.bottom >= selection.y + selection.height - tolerance
}

export function constrainTransformToSelection({ matrix, oldMatrix, selection, sourceWidth, sourceHeight }) {
  if (!Array.isArray(matrix) || matrix.length !== 6 || !matrix.every(Number.isFinite)) return null

  const [a, b, c, d, e, f] = matrix
  const dimensions = [sourceWidth, sourceHeight, selection.width, selection.height]
  if (
    !dimensions.every((value) => Number.isFinite(value) && value > 0) ||
    ![selection.x, selection.y].every(Number.isFinite) ||
    a <= 0 || Math.abs(a - d) > IMAGE_CROP_TRANSFORM_EPSILON ||
    Math.abs(b) > IMAGE_CROP_TRANSFORM_EPSILON || Math.abs(c) > IMAGE_CROP_TRANSFORM_EPSILON
  ) return null

  const minimumScale = Math.max(selection.width / sourceWidth, selection.height / sourceHeight)
  if (a >= minimumScale && transformCoversSelection({
    matrix, selection, sourceWidth, sourceHeight, tolerance: IMAGE_CROP_TRANSFORM_EPSILON,
  })) return matrix

  const scale = Math.max(a, minimumScale)
  let translateX = e
  let translateY = f

  if (a < minimumScale) {
    if (oldMatrix?.length === 6 && oldMatrix.every(Number.isFinite) && oldMatrix[0] >= minimumScale) {
      // Stop a zoom step exactly at the limit, keeping its original focal point.
      // At the limit this also prevents repeated zoom-out gestures from drifting.
      const progress = clamp((oldMatrix[0] - scale) / (oldMatrix[0] - a), 0, 1)
      translateX = oldMatrix[4] + (e - oldMatrix[4]) * progress
      translateY = oldMatrix[5] + (f - oldMatrix[5]) * progress
    } else {
      const centerX = selection.x + selection.width / 2 - sourceWidth / 2
      const centerY = selection.y + selection.height / 2 - sourceHeight / 2
      translateX = centerX - (centerX - e) * scale / a
      translateY = centerY - (centerY - f) * scale / a
    }
  }

  // Keep the image covering the fixed selection, not the larger editor canvas.
  const originX = sourceWidth * (1 - scale) / 2
  const originY = sourceHeight * (1 - scale) / 2
  const left = clamp(
    originX + translateX,
    selection.x + selection.width - sourceWidth * scale,
    selection.x
  )
  const top = clamp(
    originY + translateY,
    selection.y + selection.height - sourceHeight * scale,
    selection.y
  )

  return [scale, 0, 0, scale, left - originX, top - originY]
}

export function cropperTemplateFor(ratioKey) {
  const { ratio } = cropConfigFor(ratioKey)

  return `
    <cropper-canvas background scale-step="0.1">
      <cropper-image initial-fit="cover" scalable translatable></cropper-image>
      <cropper-shade></cropper-shade>
      <cropper-handle action="move" plain></cropper-handle>
      <cropper-selection initial-coverage="0.82" aspect-ratio="${ratio}" outlined precise>
        <cropper-grid role="grid" bordered covered></cropper-grid>
        <cropper-crosshair centered></cropper-crosshair>
        <cropper-handle action="move" plain></cropper-handle>
      </cropper-selection>
    </cropper-canvas>
  `
}

function inverseTransformPoint(x, y, matrix, sourceWidth, sourceHeight) {
  const [a, b, c, d, e, f] = matrix
  const determinant = (a * d) - (b * c)

  if (!Number.isFinite(determinant) || Math.abs(determinant) < Number.EPSILON) {
    throw cropError("invalid_transform", "画像の変換行列を座標へ変換できません。")
  }

  const centerX = sourceWidth / 2
  const centerY = sourceHeight / 2
  const translatedX = x - centerX - e
  const translatedY = y - centerY - f

  return {
    x: centerX + ((d * translatedX) - (c * translatedY)) / determinant,
    y: centerY + ((a * translatedY) - (b * translatedX)) / determinant,
  }
}

function cropError(code, message) {
  return new ImageCropStateError(code, message)
}

function round(value, precision = 4) {
  const multiplier = 10 ** precision
  return Math.round(value * multiplier) / multiplier
}

function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), maximum)
}
