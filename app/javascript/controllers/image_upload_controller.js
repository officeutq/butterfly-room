import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "removeFlag"]
  static values = {
    initialUrl: String,
    width: Number,
    height: Number,
  }

  connect() {
    this.hadInitialFile = this.hasInitialUrlValue && this.initialUrlValue.length > 0
    this.setupAttempts = 0

    setTimeout(() => {
      this.setupFilePond()
    }, 0)
  }

  disconnect() {
    if (this.setupTimer) clearTimeout(this.setupTimer)
    if (this.pond) this.pond.destroy()
  }

  setupFilePond() {
    if (this.pond) return
    if (!this.hasInputTarget) return

    if (!window.FilePond) {
      if (this.setupAttempts >= 40) return

      this.setupAttempts += 1
      this.setupTimer = setTimeout(() => {
        this.setupFilePond()
      }, 50)
      return
    }

    this.registerPlugins()

    this.pond = window.FilePond.create(this.inputTarget, {
      storeAsFile: true,
      allowMultiple: false,
      allowImagePreview: true,
      allowImageResize: true,
      allowImageTransform: true,
      allowReorder: false,
      allowProcess: false,
      allowRevert: false,

      imageResizeTargetWidth: this.widthValue || 1024,
      imageResizeTargetHeight: this.heightValue || 1024,
      imageResizeMode: "contain",
      imageResizeUpscale: false,

      imageTransformOutputMimeType: "image/jpeg",
      imageTransformOutputQuality: 94,
      imageTransformCanvasBackgroundColor: "#ffffff",

      acceptedFileTypes: [
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif",
      ],

      labelIdle: `
        <div class="image-upload-picker">
          <i class="bi bi-camera-fill image-upload-picker__icon" aria-hidden="true"></i>
        </div>
      `,
    })

    this.bindEvents()

    if (this.hadInitialFile) {
      this.pond.addFile(this.initialUrlValue).catch(() => {})
    }
  }

  bindEvents() {
    this.pond.on("addfile", () => {
      this.removeFlagTarget.value = "0"
    })

    this.pond.on("removefile", () => {
      const currentFilesCount = this.pond.getFiles().length

      if (currentFilesCount > 0) {
        this.removeFlagTarget.value = "0"
        return
      }

      this.removeFlagTarget.value = this.hadInitialFile ? "1" : "0"
    })
  }

  registerPlugins() {
    if (window.__filepondRegistered) return

    const plugins = [
      window.FilePondPluginImagePreview,
      window.FilePondPluginImageResize,
      window.FilePondPluginImageTransform,
    ].filter(Boolean)

    plugins.forEach((plugin) => {
      window.FilePond.registerPlugin(plugin)
    })

    window.__filepondRegistered = true
  }
}
