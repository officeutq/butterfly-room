import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"
import {
  IMAGE_CROP_CONFIGS,
  IMAGE_CROP_JPEG_QUALITY,
  IMAGE_CROP_TRANSFORM_EPSILON,
  constrainTransformToSelection as constrainCommonTransform,
  cropStateFromTransform as commonCropStateFromTransform,
  cropperTemplateFor,
  selectionBoxForRatio as commonSelectionBoxForRatio,
  transformFromCropState as commonTransformFromCropState,
  validateCropState,
} from "image_attachments/cropper_editor"
import { ImageSourceNormalizer } from "image_attachments/source_normalizer"
import { prepareHeicInput } from "image_attachments/heic_converter"
import { UploadVerificationClient } from "controllers/image_upload_verification/upload_client"

function roundForDisplay(value, precision = 4) {
  const multiplier = 10 ** precision
  return Math.round(value * multiplier) / multiplier
}

export default class extends Controller {
  static values = { heicWorkerUrl: String, heicDecoderUrl: String, uploadUrl: String }

  static targets = [
    "control",
    "download",
    "editor",
    "empty",
    "file",
    "heicMode",
    "heicLimit",
    "heicLimitWarning",
    "cancelConversion",
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
    "uploadTransport",
    "uploadStart",
    "uploadCancel",
    "uploadStatus",
    "uploadReport",
  ]

  connect() {
    this.cropper = null
    this.cropperCanvas = null
    this.cropperImage = null
    this.cropperSelection = null
    this.sourceObjectUrl = null
    this.previewObjectUrl = null
    // Stimulus may reconnect this same instance before a native conversion ends.
    this.loadGeneration = (this.loadGeneration || 0) + 1
    this.previewGeneration = (this.previewGeneration || 0) + 1
    this.isDisconnected = false
    this.sourceLoadCleanup = null
    this.selectedFile = null
    this.normalizationTask ||= null
    this.sourceNormalizer ||= new ImageSourceNormalizer()
    this.heicAbort = null
    this.normalizedRatioKey = null
    this.sourceBlob = null
    this.previewBlob = null
    this.uploadClient = null
    this.uploadTask = null
    this.heicLimitTarget.value = "standard"
    this.updateHeicLimit()
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
      this.setStatus("JPEG / PNG / WebP / HEIC / HEIFを選択してください。", true)
      event.currentTarget.value = ""
      return
    }

    this.selectedFile = file
    await this.normalizeSource()
  }

  async normalizeSource() {
    this.updateHeicLimit()
    const file = this.selectedFile
    if (!file || this.isDisconnected) return

    this.cancelUpload()

    const generation = this.loadGeneration + 1
    this.loadGeneration = generation
    const isCurrent = () => !this.isDisconnected && generation === this.loadGeneration
    const config = this.currentConfig()
    const ratioKey = this.ratioTarget.value
    const heicMode = this.heicModeTarget.value
    const limitMode = heicMode === "worker" ? this.heicLimitTarget.value : "standard"
    const previousTask = this.normalizationTask
    this.heicAbort?.abort()
    this.sourceNormalizer.cancel()
    const abort = new AbortController()
    this.heicAbort = abort
    this.cancelConversionTarget.disabled = false
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
        const prepared = await prepareHeicInput(file, {
          workerUrl: this.heicWorkerUrlValue, decoderUrl: this.heicDecoderUrlValue,
          signal: abort.signal, mode: heicMode, limitMode,
        })
        if (!isCurrent()) return
        const normalized = await this.sourceNormalizer.normalize(prepared.file, { ratioKey })
        if (!isCurrent()) return
        const report = {
          input: normalized.input,
          decoded: normalized.decoded,
          source: normalized.source,
          heicConversion: prepared.conversion,
        }
        this.sourceBlob = normalized.file
        this.sourceObjectUrl = URL.createObjectURL(normalized.file)
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
        // A cached image can be complete before Cropper's load/centering has
        // reached layout. Two animation frames allow the first paint to settle.
        await this.nextFrame()
        await this.nextFrame()
        if (!isCurrent()) return

        this.layoutSelection()
        this.cropperImage.addEventListener("transform", this.boundTransformGuard)
        this.cropperCanvas.addEventListener("actionend", this.boundStateUpdate)
        this.observeEditorResize()
        this.normalizedRatioKey = ratioKey
        this.renderNormalization(report, normalized.warning)
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
      } finally {
        if (isCurrent()) {
          this.cancelConversionTarget.disabled = true
          this.heicAbort = null
        }
      }
    })()
    await this.normalizationTask
  }

  async changeRatio() {
    await this.normalizeSource()
  }

  updateHeicLimit() {
    const worker = this.heicModeTarget.value === "worker"
    this.heicLimitTarget.disabled = !worker
    this.heicLimitWarningTarget.hidden = !worker || this.heicLimitTarget.value !== "large"
  }

  cancelConversion() {
    this.cleanup({ resetUi: true })
    this.setStatus("変換を中止しました。画像を選び直してください。")
  }

  renderNormalization(report, warning) {
    const source = report.source
    this.normalizationReportTarget.value = JSON.stringify(report, null, 2)
    const inputName = report.heicConversion?.input.name || report.input.name
    this.sourceMetadataTarget.textContent = `${inputName} / ${source.width}×${source.height} / ${this.formatBytes(source.bytes)} / quality ${source.quality}`
    this.normalizedPreviewTarget.src = this.sourceObjectUrl
    this.normalizedPreviewTarget.hidden = false
    this.sourceDownloadTarget.href = this.sourceObjectUrl
    this.sourceDownloadTarget.download = `source-${this.ratioTarget.value}-${source.width}x${source.height}-q${source.quality}.jpg`
    this.sourceDownloadTarget.classList.remove("disabled")
    this.sourceDownloadTarget.removeAttribute("aria-disabled")
    this.normalizationWarningTarget.textContent = warning?.message || ""
    this.normalizationWarningTarget.hidden = !this.normalizationWarningTarget.textContent
  }

  clearNormalization() {
    this.sourceBlob = null
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
      const state = this.buildState()
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
      if (JSON.stringify(state) !== JSON.stringify(this.buildState())) {
        throw new Error("生成中にクロップが変わりました。操作を止めて再度生成してください。")
      }

      this.revokePreviewObjectUrl()
      this.previewBlob = blob
      this.previewState = state
      this.previewObjectUrl = URL.createObjectURL(blob)
      this.previewTarget.src = this.previewObjectUrl
      this.previewTarget.hidden = false
      this.previewEmptyTarget.hidden = true
      this.previewMetadataTarget.textContent = `JPEG / ${config.width}×${config.height} / ${this.formatBytes(blob.size)} / quality ${IMAGE_CROP_JPEG_QUALITY}`
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
    return commonCropStateFromTransform({
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

  async startUpload() {
    if (this.uploadTask || !this.sourceBlob || !this.cropperSelection) return
    const client = new UploadVerificationClient({ url: this.uploadUrlValue, onProgress: (label, percent) => {
      if (this.uploadClient === client) this.uploadStatusTarget.textContent = `${label}${percent === null ? "…" : ` ${percent}%（転送）`}`
    } })
    this.uploadClient = client
    this.uploadStartTarget.disabled = true
    this.uploadCancelTarget.disabled = false
    this.uploadReportTarget.value = ""
    const transport = this.uploadTransportTarget.value
    const task = (async () => {
      try {
        if (!await this.generatePreview()) throw new Error("表示用JPEGを生成できませんでした。操作を止めて再試行してください。")
        client.checkCanceled()
        const report = await client.upload({ source: this.sourceBlob, display: this.previewBlob, cropData: this.previewState }, transport)
        if (this.uploadClient !== client) return
        this.uploadReportTarget.value = JSON.stringify(report, null, 2)
        this.uploadStatusTarget.textContent = "2画像の一時保存・実体確認に成功しました。測定JSONを記録してください。"
      } catch (error) {
        if (this.uploadClient === client) {
          this.uploadStatusTarget.textContent = error.message
          this.uploadReportTarget.value = JSON.stringify({ transport, state: "failed", error: error.message }, null, 2)
        }
      } finally {
        if (this.uploadClient === client) {
          this.uploadStartTarget.disabled = !this.sourceBlob
          this.uploadCancelTarget.disabled = true
          this.uploadClient = null
        }
      }
    })()
    this.uploadTask = task
    await task
    if (this.uploadTask === task) this.uploadTask = null
  }

  cancelUpload() {
    this.uploadClient?.cancel()
    this.uploadClient = null
    this.uploadTask = null
    // Optional guards also support the older isolated controller test harness.
    if (this.hasUploadStatusTarget) this.uploadStatusTarget.textContent = "未送信（送信中の場合は中止。残った画像は期限後に清掃します）"
    if (this.hasUploadReportTarget) this.uploadReportTarget.value = ""
    if (this.hasUploadCancelTarget) this.uploadCancelTarget.disabled = true
    if (this.hasUploadStartTarget) this.uploadStartTarget.disabled = !this.sourceBlob
  }

  validateState(state) {
    if (this.normalizedRatioKey && state?.ratioKey !== this.normalizedRatioKey) {
      throw new Error("正規化した編集元と同じ用途のJSONを使用してください。用途変更は画像選択欄から行えます。")
    }
    return validateCropState({
      state,
      ratioKey: state?.ratioKey,
      sourceWidth: this.sourceTarget.naturalWidth,
      sourceHeight: this.sourceTarget.naturalHeight,
    })
  }

  applyStateToImage(state) {
    const matrix = commonTransformFromCropState({
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

    const box = commonSelectionBoxForRatio({
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

    const constrained = constrainCommonTransform({
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

    if (constrained && constrained.every((value, index) => Math.abs(value - matrix[index]) <= IMAGE_CROP_TRANSFORM_EPSILON)) return

    event.preventDefault()
    if (constrained) this.cropperImage.$setTransform(constrained)
  }

  cropperTemplate(_ratio) {
    return cropperTemplateFor(this.ratioTarget.value)
  }

  supportedFile(file) {
    if (["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence"].includes(file.type)) return true

    return /\.(?:jpe?g|png|webp|heic|heif)$/i.test(file.name)
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
      }, "image/jpeg", IMAGE_CROP_JPEG_QUALITY)
    })
  }

  nextFrame() {
    return new Promise((resolve) => requestAnimationFrame(resolve))
  }

  currentConfig() {
    return IMAGE_CROP_CONFIGS[this.ratioTarget.value] || IMAGE_CROP_CONFIGS.square
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
    this.previewBlob = null
    this.previewState = null
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
    this.cancelUpload()
    this.loadGeneration += 1
    this.previewGeneration += 1
    this.heicAbort?.abort()
    this.heicAbort = null
    this.sourceNormalizer?.cancel()
    this.cancelConversionTarget.disabled = true
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
    if (bytes < 1024 ** 2) return `${roundForDisplay(bytes / 1024, 1)} KB`

    return `${roundForDisplay(bytes / (1024 ** 2), 1)} MB`
  }
}
