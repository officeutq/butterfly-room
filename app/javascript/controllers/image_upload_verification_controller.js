import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"
import { normalizeEditingSource } from "controllers/image_upload_verification/source_normalizer"

const STATE_SCHEMA_VERSION = 1
const JPEG_QUALITY = 0.9
const TRANSFORM_EPSILON = 1e-7
const RATIO_CONFIG = Object.freeze({
  square: Object.freeze({ ratio: 1, width: 1024, height: 1024 }),
  social: Object.freeze({ ratio: 40 / 21, width: 1200, height: 630 }),
})

function round(value, precision = 4) {
  const multiplier = 10 ** precision
  return Math.round(value * multiplier) / multiplier
}

function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), maximum)
}

export function normalizeCropToSource({ crop, sourceWidth, sourceHeight, tolerance = 0 }) {
  const values = [crop?.x, crop?.y, crop?.width, crop?.height, sourceWidth, sourceHeight, tolerance]

  if (!values.every(Number.isFinite) || crop.width <= 0 || crop.height <= 0) {
    throw new Error("クロップ座標が不正です。")
  }
  if (
    crop.width > sourceWidth + tolerance ||
    crop.height > sourceHeight + tolerance ||
    crop.x < -tolerance ||
    crop.y < -tolerance ||
    crop.x + crop.width > sourceWidth + tolerance ||
    crop.y + crop.height > sourceHeight + tolerance
  ) {
    throw new Error("クロップ範囲が編集元画像の外側です。")
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

function inverseTransformPoint(x, y, matrix, sourceWidth, sourceHeight) {
  const [a, b, c, d, e, f] = matrix
  const determinant = (a * d) - (b * c)

  if (!Number.isFinite(determinant) || Math.abs(determinant) < Number.EPSILON) {
    throw new Error("画像の変換行列を座標へ変換できません。")
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
  const output = RATIO_CONFIG[ratioKey]

  if (!output || rawCrop.width <= 0 || rawCrop.height <= 0) {
    throw new Error("クロップ範囲を取得できません。")
  }

  // Cropper.js may expose less than one output pixel because of subpixel rounding.
  // Shift that tiny overflow inside the source without changing the crop size or ratio.
  const tolerance = Math.max(
    rawCrop.width / output.width,
    rawCrop.height / output.height,
    1
  )
  const crop = normalizeCropToSource({ crop: rawCrop, sourceWidth, sourceHeight, tolerance })

  return {
    schemaVersion: STATE_SCHEMA_VERSION,
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
      quality: JPEG_QUALITY,
    },
  }
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
    a <= 0 || Math.abs(a - d) > TRANSFORM_EPSILON ||
    Math.abs(b) > TRANSFORM_EPSILON || Math.abs(c) > TRANSFORM_EPSILON
  ) return null

  const minimumScale = Math.max(selection.width / sourceWidth, selection.height / sourceHeight)
  if (a >= minimumScale && transformCoversSelection({
    matrix, selection, sourceWidth, sourceHeight, tolerance: TRANSFORM_EPSILON,
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

  // Keep the image covering the selection, not the larger editor canvas.
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

export default class extends Controller {
  static targets = [
    "control",
    "download",
    "editor",
    "empty",
    "file",
    "normalizationQuality",
    "normalizationMode",
    "normalizationReport",
    "normalizationWarning",
    "normalizedPreview",
    "preview",
    "previewEmpty",
    "previewMetadata",
    "ratio",
    "source",
    "sourceDownload",
    "sourceMetadata",
    "state",
    "status",
    "workspace",
  ]

  connect() {
    this.cropper = null
    this.cropperCanvas = null
    this.cropperImage = null
    this.cropperSelection = null
    this.sourceObjectUrl = null
    this.previewObjectUrl = null
    this.loadGeneration = 0
    this.previewGeneration = 0
    this.isDisconnected = false
    this.sourceLoadCleanup = null
    this.selectedFile = null
    this.normalizationTask = null
    this.normalizedRatioKey = null
    this.boundTransformGuard = this.constrainTransform.bind(this)
    this.boundStateUpdate = this.updateStateAfterOperation.bind(this)
    this.setControlsDisabled(true)
  }

  disconnect() {
    this.isDisconnected = true
    this.cleanup()
  }

  beforeCache() {
    this.cleanup({ resetUi: true })
  }

  async loadFile(event) {
    const file = event.currentTarget.files?.[0]
    if (!file) return

    if (!this.supportedFile(file)) {
      this.setStatus("JPEG / PNG / WebPを選択してください。", true)
      event.currentTarget.value = ""
      return
    }

    this.selectedFile = file
    await this.normalizeSource()
  }

  async normalizeSource() {
    const file = this.selectedFile
    if (!file || this.isDisconnected) return

    const generation = this.loadGeneration + 1
    this.loadGeneration = generation
    const isCurrent = () => !this.isDisconnected && generation === this.loadGeneration
    const config = this.currentConfig()
    const ratioKey = this.ratioTarget.value
    const quality = Number(this.normalizationQualityTarget.value)
    const mode = this.normalizationModeTarget.value
    const previousTask = this.normalizationTask
    this.clearPendingSourceLoad()
    this.destroyCropper()
    this.revokeSourceObjectUrl()
    this.clearNormalization()
    this.clearPreview()
    this.stateTarget.value = ""
    this.sourceTarget.removeAttribute("src")
    this.workspaceTarget.hidden = true
    this.emptyTarget.hidden = false
    this.setControlsDisabled(true)
    this.setStatus("編集元JPEGへ変換しています…")

    // Serialize native decoding/encoding: changing settings cannot allocate
    // several full-resolution bitmaps at once. Only the latest result is used.
    this.normalizationTask = (async () => {
      await previousTask
      if (!isCurrent()) return
      try {
        const { blob, report } = await normalizeEditingSource(file, {
          minimumWidth: config.width, minimumHeight: config.height, quality, mode, isCurrent,
        })
        if (!isCurrent()) return
        this.sourceObjectUrl = URL.createObjectURL(blob)
        this.sourceTarget.src = this.sourceObjectUrl
        this.emptyTarget.hidden = true
        this.workspaceTarget.hidden = false

        await this.waitForSourceImage()
        if (!isCurrent()) return

        this.cropper = new Cropper(this.sourceTarget, {
          container: this.editorTarget,
          template: this.cropperTemplate(config.ratio),
        })
        this.cropperCanvas = this.cropper.getCropperCanvas()
        this.cropperImage = this.cropper.getCropperImage()
        this.cropperSelection = this.cropper.getCropperSelection()

        if (!this.cropperCanvas || !this.cropperImage || !this.cropperSelection) {
          throw new Error("Cropper.jsの編集要素を初期化できません。")
        }

        await this.cropperImage.$ready()
        if (!isCurrent()) return

        this.layoutSelection()
        this.cropperImage.addEventListener("transform", this.boundTransformGuard)
        this.cropperCanvas.addEventListener("actionend", this.boundStateUpdate)
        this.observeEditorResize()
        this.normalizedRatioKey = ratioKey
        this.renderNormalization(report)
        this.setControlsDisabled(false)
        this.captureState()
        const generated = await this.generatePreview()
        if (isCurrent() && generated) this.setStatus("操作できます（編集元JPEGへ正規化済み）")
      } catch (error) {
        if (!isCurrent()) return

        this.destroyCropper()
        this.revokeSourceObjectUrl()
        this.clearNormalization()
        this.sourceTarget.removeAttribute("src")
        this.workspaceTarget.hidden = true
        this.emptyTarget.hidden = false
        this.setControlsDisabled(true)
        this.setStatus(error.message || "画像を読み込めませんでした。", true)
      }
    })()
    await this.normalizationTask
  }

  async changeRatio() {
    await this.normalizeSource()
  }

  renderNormalization(report) {
    const source = report.source
    this.normalizationReportTarget.value = JSON.stringify(report, null, 2)
    this.sourceMetadataTarget.textContent = `${report.input.name} / ${source.width}×${source.height} / ${this.formatBytes(source.bytes)} / quality ${source.quality} / ${report.milliseconds.total}ms`
    this.normalizedPreviewTarget.src = this.sourceObjectUrl
    this.normalizedPreviewTarget.hidden = false
    this.sourceDownloadTarget.href = this.sourceObjectUrl
    this.sourceDownloadTarget.download = `source-${this.ratioTarget.value}-${source.width}x${source.height}-q${source.quality}.jpg`
    this.sourceDownloadTarget.classList.remove("disabled")
    this.sourceDownloadTarget.removeAttribute("aria-disabled")
    this.normalizationWarningTarget.textContent = source.enlarged
      ? `小さい画像を約${round(source.scale, 2)}倍に拡大しました。登録は妨げませんが、細部の解像感は増えません。`
      : source.reduced ? "大きい画像を暫定上限まで縮小しました。元寸法を保つ設定とも比較してください。" : ""
    this.normalizationWarningTarget.hidden = !this.normalizationWarningTarget.textContent
  }

  clearNormalization() {
    this.normalizedRatioKey = null
    this.normalizedPreviewTarget.removeAttribute("src")
    this.normalizedPreviewTarget.hidden = true
    this.normalizationReportTarget.value = ""
    this.normalizationWarningTarget.textContent = ""
    this.normalizationWarningTarget.hidden = true
    this.sourceMetadataTarget.textContent = "-"
    this.sourceDownloadTarget.removeAttribute("href")
    this.sourceDownloadTarget.removeAttribute("download")
    this.sourceDownloadTarget.classList.add("disabled")
    this.sourceDownloadTarget.setAttribute("aria-disabled", "true")
  }

  zoomIn() {
    this.cropperImage?.$zoom(0.1)
    this.captureState()
  }

  zoomOut() {
    this.cropperImage?.$zoom(-0.1)
    this.captureState()
  }

  async reset() {
    if (!this.cropperImage) return

    this.resetImageTransform()
    this.captureState()
    if (await this.generatePreview()) this.setStatus("初期状態へ戻しました")
  }

  captureState() {
    if (!this.cropperImage || !this.cropperSelection) return null

    try {
      const state = this.buildState()
      this.stateTarget.value = JSON.stringify(state, null, 2)
      return state
    } catch (error) {
      this.setStatus(error.message, true)
      return null
    }
  }

  async restoreState() {
    if (!this.cropperImage || !this.cropperSelection) return
    const generation = this.loadGeneration

    try {
      const state = this.validateState(JSON.parse(this.stateTarget.value))
      this.ratioTarget.value = state.ratioKey
      this.cropperSelection.aspectRatio = this.currentConfig().ratio
      await this.nextFrame()
      if (!this.cropperSelection || this.isDisconnected || generation !== this.loadGeneration) return

      this.layoutSelection()
      this.applyStateToImage(state)
      this.captureState()
      if (await this.generatePreview()) this.setStatus("JSONのクロップ状態を復元しました")
    } catch (error) {
      if (generation !== this.loadGeneration) return
      this.setStatus(error.message || "クロップ状態を復元できませんでした。", true)
    }
  }

  async generatePreview() {
    if (!this.cropperSelection) return

    const config = this.currentConfig()
    const generation = this.previewGeneration + 1
    this.previewGeneration = generation

    try {
      const canvas = await this.cropperSelection.$toCanvas({
        width: config.width,
        height: config.height,
        beforeDraw(context, outputCanvas) {
          context.fillStyle = "#ffffff"
          context.fillRect(0, 0, outputCanvas.width, outputCanvas.height)
        },
      })
      const blob = await this.canvasToJpeg(canvas)
      if (this.isDisconnected || generation !== this.previewGeneration) return

      this.revokePreviewObjectUrl()
      this.previewObjectUrl = URL.createObjectURL(blob)
      this.previewTarget.src = this.previewObjectUrl
      this.previewTarget.hidden = false
      this.previewEmptyTarget.hidden = true
      this.previewMetadataTarget.textContent = `JPEG / ${config.width}×${config.height} / ${this.formatBytes(blob.size)} / quality ${JPEG_QUALITY}`
      this.downloadTarget.href = this.previewObjectUrl
      this.downloadTarget.download = `crop-${this.ratioTarget.value}-${config.width}x${config.height}.jpg`
      this.downloadTarget.classList.remove("disabled")
      this.downloadTarget.removeAttribute("aria-disabled")
      return true
    } catch (error) {
      if (generation !== this.previewGeneration) return
      this.setStatus(error.message || "表示用JPEGを生成できませんでした。", true)
    }
  }

  buildState() {
    return cropStateFromTransform({
      selection: {
        x: this.cropperSelection.x,
        y: this.cropperSelection.y,
        width: this.cropperSelection.width,
        height: this.cropperSelection.height,
      },
      matrix: this.cropperImage.$getTransform(),
      sourceWidth: this.sourceTarget.naturalWidth,
      sourceHeight: this.sourceTarget.naturalHeight,
      ratioKey: this.ratioTarget.value,
    })
  }

  validateState(state) {
    if (this.normalizedRatioKey && state?.ratioKey !== this.normalizedRatioKey) {
      throw new Error("正規化した編集元と同じ用途のJSONを使用してください。用途変更は画像選択欄から行えます。")
    }
    const numbers = [
      state?.source?.width,
      state?.source?.height,
      state?.crop?.x,
      state?.crop?.y,
      state?.crop?.width,
      state?.crop?.height,
    ]

    if (state?.schemaVersion !== STATE_SCHEMA_VERSION || !RATIO_CONFIG[state?.ratioKey]) {
      throw new Error("対応していないクロップ状態です。")
    }
    if (!numbers.every(Number.isFinite) || state.crop.width <= 0 || state.crop.height <= 0) {
      throw new Error("クロップ座標が不正です。")
    }
    if (
      state.source.width !== this.sourceTarget.naturalWidth ||
      state.source.height !== this.sourceTarget.naturalHeight
    ) {
      throw new Error("編集元画像のサイズがJSONと一致しません。")
    }

    const output = RATIO_CONFIG[state.ratioKey]
    const tolerance = Math.max(
      state.crop.width / output.width,
      state.crop.height / output.height,
      1
    )
    const crop = normalizeCropToSource({
      crop: state.crop,
      sourceWidth: state.source.width,
      sourceHeight: state.source.height,
      tolerance,
    })

    return { ...state, crop }
  }

  applyStateToImage(state) {
    const matrix = transformFromCropState({
      crop: state.crop,
      selection: {
        x: this.cropperSelection.x,
        y: this.cropperSelection.y,
        width: this.cropperSelection.width,
        height: this.cropperSelection.height,
      },
      sourceWidth: state.source.width,
      sourceHeight: state.source.height,
    })
    this.cropperImage.$setTransform(matrix)
  }

  layoutSelection() {
    if (!this.cropperCanvas || !this.cropperSelection) return

    const box = selectionBoxForRatio({
      canvasWidth: this.cropperCanvas.clientWidth,
      canvasHeight: this.cropperCanvas.clientHeight,
      ratio: this.currentConfig().ratio,
    })
    this.cropperSelection.$change(
      box.x,
      box.y,
      box.width,
      box.height,
      this.currentConfig().ratio,
      true
    )
  }

  resetImageTransform() {
    this.cropperImage.$resetTransform()
    this.cropperImage.$center("cover")
  }

  observeEditorResize() {
    if (typeof ResizeObserver === "undefined") return

    this.resizeObserver?.disconnect()
    this.resizeObserver = new ResizeObserver(() => {
      if (!this.cropperSelection || !this.cropperImage) return

      const state = this.buildState()
      this.layoutSelection()
      this.applyStateToImage(state)
      this.captureState()
    })
    this.resizeObserver.observe(this.editorTarget)
  }

  updateStateAfterOperation() {
    this.captureState()
  }

  constrainTransform(event) {
    const matrix = event.detail?.matrix
    if (!matrix || !this.cropperSelection || !this.cropperImage) return

    const constrained = constrainTransformToSelection({
      matrix,
      oldMatrix: event.detail.oldMatrix,
      selection: {
        x: this.cropperSelection.x,
        y: this.cropperSelection.y,
        width: this.cropperSelection.width,
        height: this.cropperSelection.height,
      },
      sourceWidth: this.sourceTarget.naturalWidth,
      sourceHeight: this.sourceTarget.naturalHeight,
    })

    if (constrained && constrained.every((value, index) => Math.abs(value - matrix[index]) <= TRANSFORM_EPSILON)) return

    event.preventDefault()
    if (constrained) this.cropperImage.$setTransform(constrained)
  }

  cropperTemplate(ratio) {
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

  supportedFile(file) {
    if (["image/jpeg", "image/png", "image/webp"].includes(file.type)) return true

    return /\.(?:jpe?g|png|webp)$/i.test(file.name)
  }

  waitForSourceImage() {
    if (this.sourceTarget.complete && this.sourceTarget.naturalWidth > 0) {
      return Promise.resolve()
    }

    return new Promise((resolve, reject) => {
      const onLoad = () => {
        this.clearPendingSourceLoad(false)
        resolve()
      }
      const onError = () => {
        this.clearPendingSourceLoad(false)
        reject(new Error("ブラウザで画像を読み込めませんでした。"))
      }

      this.sourceLoadCleanup = (cancel) => {
        this.sourceTarget.removeEventListener("load", onLoad)
        this.sourceTarget.removeEventListener("error", onError)
        if (cancel) reject(new Error("編集元画像の読み込みを中止しました。"))
      }
      this.sourceTarget.addEventListener("load", onLoad)
      this.sourceTarget.addEventListener("error", onError)
    })
  }

  clearPendingSourceLoad(cancel = true) {
    this.sourceLoadCleanup?.(cancel)
    this.sourceLoadCleanup = null
  }

  canvasToJpeg(canvas) {
    return new Promise((resolve, reject) => {
      canvas.toBlob((blob) => {
        if (blob) {
          resolve(blob)
        } else {
          reject(new Error("JPEGへの変換に失敗しました。"))
        }
      }, "image/jpeg", JPEG_QUALITY)
    })
  }

  nextFrame() {
    return new Promise((resolve) => requestAnimationFrame(resolve))
  }

  currentConfig() {
    return RATIO_CONFIG[this.ratioTarget.value] || RATIO_CONFIG.square
  }

  setControlsDisabled(disabled) {
    this.controlTargets.forEach((control) => {
      control.disabled = disabled
    })
  }

  setStatus(message, error = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-danger", error)
  }

  clearPreview() {
    this.previewGeneration += 1
    this.revokePreviewObjectUrl()
    this.previewTarget.removeAttribute("src")
    this.previewTarget.hidden = true
    this.previewEmptyTarget.hidden = false
    this.previewMetadataTarget.textContent = "-"
    this.downloadTarget.removeAttribute("href")
    this.downloadTarget.removeAttribute("download")
    this.downloadTarget.classList.add("disabled")
    this.downloadTarget.setAttribute("aria-disabled", "true")
  }

  destroyCropper() {
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    this.cropperImage?.removeEventListener("transform", this.boundTransformGuard)
    this.cropperCanvas?.removeEventListener("actionend", this.boundStateUpdate)
    this.cropper?.destroy()
    this.cropper = null
    this.cropperCanvas = null
    this.cropperImage = null
    this.cropperSelection = null
  }

  cleanup({ resetUi = false } = {}) {
    this.loadGeneration += 1
    this.previewGeneration += 1
    this.clearPendingSourceLoad()
    this.destroyCropper()
    this.revokeSourceObjectUrl()
    this.selectedFile = null
    this.clearNormalization()
    this.clearPreview()
    this.setControlsDisabled(true)

    if (resetUi) {
      this.fileTarget.value = ""
      this.sourceTarget.removeAttribute("src")
      this.sourceMetadataTarget.textContent = "-"
      this.stateTarget.value = ""
      this.workspaceTarget.hidden = true
      this.emptyTarget.hidden = false
      this.setStatus("画像未選択")
    }
  }

  revokeSourceObjectUrl() {
    if (!this.sourceObjectUrl) return

    URL.revokeObjectURL(this.sourceObjectUrl)
    this.sourceObjectUrl = null
  }

  revokePreviewObjectUrl() {
    if (!this.previewObjectUrl) return

    URL.revokeObjectURL(this.previewObjectUrl)
    this.previewObjectUrl = null
  }

  formatBytes(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 ** 2) return `${round(bytes / 1024, 1)} KB`

    return `${round(bytes / (1024 ** 2), 1)} MB`
  }
}
