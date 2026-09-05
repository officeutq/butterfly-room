import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"
import {
  IMAGE_CROP_JPEG_QUALITY,
  IMAGE_CROP_TRANSFORM_EPSILON,
  constrainTransformToSelection,
  cropConfigFor,
  cropStateFromTransform,
  cropperTemplateFor,
  selectionBoxForRatio,
  transformFromCropState,
  validateCropState,
} from "image_attachments/cropper_editor"
import { ImageSourceNormalizer } from "image_attachments/source_normalizer"
import { ImageHeicConverter } from "image_attachments/heic_converter"

const ACCEPTED_FILE_TYPES = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence"]
const ACCEPTED_FILE_EXTENSION = /\.(?:jpe?g|png|webp|hei[cf])$/i

export default class extends Controller {
  static targets = [
    "applyButton",
    "cropDataInput",
    "currentPreview",
    "deleteButton",
    "deletionNotice",
    "displayInput",
    "editButton",
    "editor",
    "editorControl",
    "fileInput",
    "operationInput",
    "previewEmpty",
    "source",
    "sourceInput",
    "status",
    "undoButton",
    "warning",
    "workspace",
  ]

  static values = {
    currentCropData: String,
    currentDisplayUrl: String,
    currentSourceBlobId: Number,
    currentSourceUrl: String,
    heicDecoderUrl: String,
    heicWorkerUrl: String,
    ratioKey: String,
  }

  connect() {
    this.isDisconnected = false
    this.generation = (this.generation || 0) + 1
    this.previewGeneration = (this.previewGeneration || 0) + 1
    this.sourceNormalizer ||= new ImageSourceNormalizer()
    this.heicConverter ||= new ImageHeicConverter({
      workerUrl: this.heicWorkerUrlValue,
      decoderUrl: this.heicDecoderUrlValue,
    })
    this.sourceLoadCleanup = null
    this.cropper = null
    this.cropperCanvas = null
    this.cropperImage = null
    this.cropperSelection = null
    this.resizeObserver = null
    this.workingSourceFile = null
    this.workingSourceObjectUrl = null
    this.previewObjectUrl = null
    this.phase = "idle"
    this.boundTransformGuard = this.constrainTransform.bind(this)
    this.boundActionEnd = this.updateDraftStatus.bind(this)
    this.boundFormSubmit = this.validateFormSubmit.bind(this)
    this.form = this.element.closest("form")
    this.form?.addEventListener("submit", this.boundFormSubmit)

    try {
      cropConfigFor(this.ratioKeyValue)
      this.resetToBaseline({ announce: false })
    } catch (error) {
      this.renderError(error.message)
      this.setEditorControlsDisabled(true)
    }
  }

  disconnect() {
    this.isDisconnected = true
    this.form?.removeEventListener("submit", this.boundFormSubmit)
    this.form = null
    this.releaseWorkingResources()
  }

  beforeCache() {
    this.resetToBaseline({ announce: false })
  }

  async selectFile(event) {
    const file = event.currentTarget.files?.[0]
    if (!file) return
    if (!this.supportedFile(file)) {
      this.resetToBaseline({ announce: false })
      this.renderError("JPEG / PNG / WebP / HEIC / HEIFを選択してください。")
      return
    }

    this.resetToBaseline({ announce: false, preservePicker: true })
    const generation = this.generation
    this.phase = "processing"
    this.setEditorControlsDisabled(true)
    this.renderStatus("画像を確認し、編集元JPEGを準備しています…")
    try {
      const prepared = await this.heicConverter.prepare(file)
      if (!this.isCurrent(generation)) return

      const normalized = await this.sourceNormalizer.normalize(prepared.file, { ratioKey: this.ratioKeyValue })
      if (!this.isCurrent(generation)) return

      this.workingSourceFile = normalized.file
      this.workingSourceObjectUrl = URL.createObjectURL(normalized.file)
      await this.initializeEditor({
        sourceUrl: this.workingSourceObjectUrl,
        kind: "replacement",
        generation,
      })
      if (!this.isCurrent(generation)) return

      this.renderWarning(normalized.warning?.message || "")
      this.renderStatus("画像を移動・拡大縮小して、構図を確定してください。")
    } catch (error) {
      if (!this.isCurrent(generation)) return

      this.releaseEditor()
      this.workspaceTarget.hidden = true
      this.revokeWorkingSourceObjectUrl()
      this.workingSourceFile = null
      this.fileInputTarget.value = ""
      this.phase = "idle"
      this.renderError(error.message || "画像を読み込めませんでした。")
    }
  }

  async editExisting() {
    if (!this.canEditCurrentImage()) return

    this.resetToBaseline({ announce: false })
    const generation = this.generation
    this.phase = "processing"
    this.setEditorControlsDisabled(true)
    this.renderStatus("現在の編集元画像を読み込んでいます…")
    try {
      const state = JSON.parse(this.currentCropDataValue)
      await this.initializeEditor({
        sourceUrl: this.currentSourceUrlValue,
        state,
        kind: "existing",
        generation,
      })
      if (!this.isCurrent(generation)) return

      this.renderStatus("前回の構図を復元しました。画像を移動・拡大縮小できます。")
    } catch (error) {
      if (!this.isCurrent(generation)) return

      this.releaseEditor()
      this.workspaceTarget.hidden = true
      this.phase = "idle"
      this.renderError(error.message || "現在の画像を再編集できませんでした。")
    }
  }

  zoomIn() {
    this.cropperImage?.$zoom(0.1)
    this.updateDraftStatus()
  }

  zoomOut() {
    this.cropperImage?.$zoom(-0.1)
    this.updateDraftStatus()
  }

  moveWithKeyboard(event) {
    if (!this.cropperImage) return

    const movements = {
      ArrowLeft: [-10, 0],
      ArrowRight: [10, 0],
      ArrowUp: [0, -10],
      ArrowDown: [0, 10],
    }
    if (movements[event.key]) {
      event.preventDefault()
      this.cropperImage.$move(...movements[event.key])
      this.updateDraftStatus()
      return
    }
    if (["+", "="].includes(event.key)) {
      event.preventDefault()
      this.zoomIn()
    } else if (["-", "_"].includes(event.key)) {
      event.preventDefault()
      this.zoomOut()
    }
  }

  resetImage() {
    if (!this.cropperImage) return

    this.cropperImage.$resetTransform()
    this.cropperImage.$center("cover")
    this.updateDraftStatus()
  }

  async applyCrop() {
    if (!this.phase.startsWith("editing-") || !this.cropperSelection) return

    const generation = this.generation
    const previewGeneration = this.previewGeneration + 1
    this.previewGeneration = previewGeneration
    this.applyButtonTarget.disabled = true
    this.renderStatus("表示用JPEGを生成しています…")
    let canvas
    try {
      const state = this.buildState()
      const { width, height } = cropConfigFor(this.ratioKeyValue)
      canvas = await this.cropperSelection.$toCanvas({
        width,
        height,
        beforeDraw(context, outputCanvas) {
          context.fillStyle = "#ffffff"
          context.fillRect(0, 0, outputCanvas.width, outputCanvas.height)
        },
      })
      const blob = await this.canvasToJpeg(canvas)
      if (!this.isCurrent(generation) || previewGeneration !== this.previewGeneration) return
      if (JSON.stringify(state) !== JSON.stringify(this.buildState())) {
        throw new Error("生成中に構図が変わりました。操作を止めて再度確定してください。")
      }

      const displayFile = new File([blob], "display.jpg", { type: "image/jpeg" })
      const replacement = this.phase === "editing-replacement"
      this.setInputFile(this.sourceInputTarget, replacement ? this.workingSourceFile : null)
      this.setInputFile(this.displayInputTarget, displayFile)
      this.cropDataInputTarget.value = JSON.stringify(state)
      this.operationInputTarget.value = replacement ? "replace" : "reedit"
      this.revokePreviewObjectUrl()
      this.previewObjectUrl = URL.createObjectURL(displayFile)
      this.currentPreviewTarget.src = this.previewObjectUrl
      this.currentPreviewTarget.hidden = false
      this.previewEmptyTarget.hidden = true
      this.deletionNoticeTarget.hidden = true
      this.phase = replacement ? "staged-replace" : "staged-reedit"
      this.releaseEditor()
      this.revokeWorkingSourceObjectUrl()
      this.workingSourceFile = null
      this.workspaceTarget.hidden = true
      this.editButtonTarget.hidden = true
      this.deleteButtonTarget.hidden = true
      this.undoButtonTarget.hidden = false
      this.renderWarning("")
      this.renderStatus("画像の変更を反映しました。最後にフォームの保存ボタンを押してください。")
      this.dispatch("change", { detail: { operation: this.operationInputTarget.value } })
    } catch (error) {
      if (!this.isCurrent(generation) || previewGeneration !== this.previewGeneration) return

      this.renderError(error.message || "表示用JPEGを生成できませんでした。")
      this.applyButtonTarget.disabled = false
    } finally {
      if (canvas) {
        canvas.width = 0
        canvas.height = 0
      }
    }
  }

  cancelEdit() {
    this.resetToBaseline()
  }

  removeImage() {
    if (!this.hasCurrentDisplayImage()) return

    this.resetToBaseline({ announce: false })
    this.operationInputTarget.value = "delete"
    this.currentPreviewTarget.removeAttribute("src")
    this.currentPreviewTarget.hidden = true
    this.previewEmptyTarget.hidden = true
    this.deletionNoticeTarget.hidden = false
    this.editButtonTarget.hidden = true
    this.deleteButtonTarget.hidden = true
    this.undoButtonTarget.hidden = false
    this.phase = "staged-delete"
    this.renderStatus("画像を削除対象にしました。最後にフォームの保存ボタンを押してください。")
    this.dispatch("change", { detail: { operation: "delete" } })
  }

  undoChange() {
    this.resetToBaseline()
  }

  validateFormSubmit(event) {
    if (this.phase === "processing" || this.phase.startsWith("editing-")) {
      event.preventDefault()
      event.imageAttachmentEditorInvalid = true
      this.renderError("画像の構図を確定するか、画像編集をキャンセルしてから保存してください。")
      this.statusTarget.focus()
      return
    }

    const operation = this.operationInputTarget.value
    const sourceCount = this.sourceInputTarget.files?.length || 0
    const displayCount = this.displayInputTarget.files?.length || 0
    const hasCropData = this.cropDataInputTarget.value.length > 0
    const valid = operation === "" ||
      (operation === "replace" && sourceCount === 1 && displayCount === 1 && hasCropData) ||
      (operation === "reedit" && sourceCount === 0 && displayCount === 1 && hasCropData) ||
      (operation === "delete" && sourceCount === 0 && displayCount === 0 && !hasCropData)
    if (valid) return

    event.preventDefault()
    event.imageAttachmentEditorInvalid = true
    this.renderError("画像の送信準備が完了していません。画像の変更をやり直してください。")
    this.statusTarget.focus()
  }

  async initializeEditor({ sourceUrl, state = null, kind, generation }) {
    this.releaseEditor()
    this.workspaceTarget.hidden = false
    this.sourceTarget.src = sourceUrl
    await this.waitForSourceImage()
    if (!this.isCurrent(generation)) return

    const config = cropConfigFor(this.ratioKeyValue)
    this.cropper = new Cropper(this.sourceTarget, {
      container: this.editorTarget,
      template: cropperTemplateFor(this.ratioKeyValue),
    })
    this.cropperCanvas = this.cropper.getCropperCanvas()
    this.cropperImage = this.cropper.getCropperImage()
    this.cropperSelection = this.cropper.getCropperSelection()
    if (!this.cropperCanvas || !this.cropperImage || !this.cropperSelection) {
      throw new Error("画像編集画面を初期化できません。")
    }

    await this.cropperImage.$ready()
    await this.nextFrame()
    await this.nextFrame()
    if (!this.isCurrent(generation)) return

    this.layoutSelection(config.ratio)
    if (state) {
      const validated = validateCropState({
        state,
        ratioKey: this.ratioKeyValue,
        sourceWidth: this.sourceTarget.naturalWidth,
        sourceHeight: this.sourceTarget.naturalHeight,
        sourceBlobId: this.currentSourceBlobIdValue,
      })
      this.applyStateToImage(validated)
    } else {
      this.cropperImage.$resetTransform()
      this.cropperImage.$center("cover")
    }
    this.cropperImage.addEventListener("transform", this.boundTransformGuard)
    this.cropperCanvas.addEventListener("actionend", this.boundActionEnd)
    this.observeEditorResize()
    this.phase = `editing-${kind}`
    this.setEditorControlsDisabled(false)
  }

  buildState() {
    return cropStateFromTransform({
      selection: this.selectionBounds(),
      matrix: this.cropperImage.$getTransform(),
      sourceWidth: this.sourceTarget.naturalWidth,
      sourceHeight: this.sourceTarget.naturalHeight,
      ratioKey: this.ratioKeyValue,
    })
  }

  applyStateToImage(state) {
    this.cropperImage.$setTransform(transformFromCropState({
      crop: state.crop,
      selection: this.selectionBounds(),
      sourceWidth: state.source.width,
      sourceHeight: state.source.height,
    }))
  }

  layoutSelection(ratio = cropConfigFor(this.ratioKeyValue).ratio) {
    if (!this.cropperCanvas || !this.cropperSelection) return

    const box = selectionBoxForRatio({
      canvasWidth: this.cropperCanvas.clientWidth,
      canvasHeight: this.cropperCanvas.clientHeight,
      ratio,
    })
    this.cropperSelection.$change(box.x, box.y, box.width, box.height, ratio, true)
  }

  observeEditorResize() {
    if (typeof ResizeObserver === "undefined") return

    this.resizeObserver?.disconnect()
    this.resizeObserver = new ResizeObserver(() => {
      if (!this.cropperSelection || !this.cropperImage) return

      try {
        const state = this.buildState()
        this.layoutSelection()
        this.applyStateToImage(state)
      } catch (error) {
        this.renderError(error.message)
      }
    })
    this.resizeObserver.observe(this.editorTarget)
  }

  constrainTransform(event) {
    const matrix = event.detail?.matrix
    if (!matrix || !this.cropperSelection || !this.cropperImage) return

    const constrained = constrainTransformToSelection({
      matrix,
      oldMatrix: event.detail.oldMatrix,
      selection: this.selectionBounds(),
      sourceWidth: this.sourceTarget.naturalWidth,
      sourceHeight: this.sourceTarget.naturalHeight,
    })
    if (constrained && constrained.every((value, index) =>
      Math.abs(value - matrix[index]) <= IMAGE_CROP_TRANSFORM_EPSILON
    )) return

    event.preventDefault()
    if (constrained) this.cropperImage.$setTransform(constrained)
  }

  selectionBounds() {
    return {
      x: this.cropperSelection.x,
      y: this.cropperSelection.y,
      width: this.cropperSelection.width,
      height: this.cropperSelection.height,
    }
  }

  waitForSourceImage() {
    if (this.sourceTarget.complete && this.sourceTarget.naturalWidth > 0) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const onLoad = () => {
        this.clearPendingSourceLoad(false)
        resolve()
      }
      const onError = () => {
        this.clearPendingSourceLoad(false)
        reject(new Error("編集元画像を読み込めませんでした。"))
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
        if (blob?.type === "image/jpeg" && blob.size > 0) resolve(blob)
        else reject(new Error("表示用JPEGを生成できませんでした。"))
      }, "image/jpeg", IMAGE_CROP_JPEG_QUALITY)
    })
  }

  setInputFile(input, file) {
    if (!file) {
      input.value = ""
      return
    }

    const transfer = new DataTransfer()
    transfer.items.add(file)
    input.files = transfer.files
  }

  resetToBaseline({ announce = true, preservePicker = false } = {}) {
    this.releaseWorkingResources()
    this.clearPayloadInputs()
    if (!preservePicker) this.fileInputTarget.value = ""
    this.deletionNoticeTarget.hidden = true
    this.undoButtonTarget.hidden = true
    this.workspaceTarget.hidden = true
    const hasCurrent = this.hasCurrentDisplayImage()
    if (hasCurrent) {
      this.currentPreviewTarget.src = this.currentDisplayUrlValue
      this.currentPreviewTarget.hidden = false
      this.previewEmptyTarget.hidden = true
    } else {
      this.currentPreviewTarget.removeAttribute("src")
      this.currentPreviewTarget.hidden = true
      this.previewEmptyTarget.hidden = false
    }
    this.editButtonTarget.hidden = !this.canEditCurrentImage()
    this.deleteButtonTarget.hidden = !hasCurrent
    this.phase = "idle"
    this.renderWarning("")
    if (announce) this.renderStatus(hasCurrent ? "画像の変更を取り消しました。" : "画像未選択です。")
    else this.renderStatus(hasCurrent ? "現在の画像です。" : "画像未選択です。")
    this.dispatch("change", { detail: { operation: "" } })
  }

  clearPayloadInputs() {
    this.operationInputTarget.value = ""
    this.cropDataInputTarget.value = ""
    this.setInputFile(this.sourceInputTarget, null)
    this.setInputFile(this.displayInputTarget, null)
  }

  hasCurrentDisplayImage() {
    return this.hasCurrentDisplayUrlValue && this.currentDisplayUrlValue.length > 0
  }

  canEditCurrentImage() {
    return this.hasCurrentDisplayImage() &&
      this.hasCurrentSourceUrlValue && this.currentSourceUrlValue.length > 0 &&
      this.hasCurrentCropDataValue && this.currentCropDataValue.length > 0 &&
      this.hasCurrentSourceBlobIdValue && Number.isSafeInteger(this.currentSourceBlobIdValue) &&
      this.currentSourceBlobIdValue > 0
  }

  supportedFile(file) {
    return ACCEPTED_FILE_TYPES.includes(file.type) || ACCEPTED_FILE_EXTENSION.test(file.name || "")
  }

  updateDraftStatus() {
    if (this.phase.startsWith("editing-")) this.renderStatus("構図を調整中です。確定するとフォームへ反映されます。")
  }

  setEditorControlsDisabled(disabled) {
    this.editorControlTargets.forEach((control) => { control.disabled = disabled })
  }

  renderStatus(message) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.remove("text-danger")
  }

  renderError(message) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.add("text-danger")
  }

  renderWarning(message) {
    this.warningTarget.textContent = message
    this.warningTarget.hidden = message.length === 0
  }

  releaseEditor() {
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    this.clearPendingSourceLoad()
    this.cropperImage?.removeEventListener("transform", this.boundTransformGuard)
    this.cropperCanvas?.removeEventListener("actionend", this.boundActionEnd)
    this.cropper?.destroy()
    this.cropper = null
    this.cropperCanvas = null
    this.cropperImage = null
    this.cropperSelection = null
    this.sourceTarget.removeAttribute("src")
  }

  releaseWorkingResources() {
    this.generation += 1
    this.previewGeneration += 1
    this.sourceNormalizer?.cancel()
    this.heicConverter?.cancel()
    this.releaseEditor()
    this.revokeWorkingSourceObjectUrl()
    this.revokePreviewObjectUrl()
    this.workingSourceFile = null
  }

  revokeWorkingSourceObjectUrl() {
    if (!this.workingSourceObjectUrl) return

    URL.revokeObjectURL(this.workingSourceObjectUrl)
    this.workingSourceObjectUrl = null
  }

  revokePreviewObjectUrl() {
    if (!this.previewObjectUrl) return

    URL.revokeObjectURL(this.previewObjectUrl)
    this.previewObjectUrl = null
  }

  isCurrent(generation) {
    return !this.isDisconnected && generation === this.generation
  }

  nextFrame() {
    return new Promise((resolve) => requestAnimationFrame(resolve))
  }
}
