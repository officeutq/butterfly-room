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
    this.initialFileRetryAttempted = false
    this.suppressRemoveFlagUpdate = false
    this.isDisconnected = false

    setTimeout(() => {
      this.setupFilePond()
    }, 0)
  }

  disconnect() {
    this.isDisconnected = true
    if (this.setupTimer) clearTimeout(this.setupTimer)
    if (this.pond) {
      this.pond.destroy()
      this.pond = null
    }
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
      this.loadInitialFile()
    }
  }

  bindEvents() {
    this.pond.on("addfile", () => {
      this.removeFlagTarget.value = "0"
    })

    this.pond.on("removefile", () => {
      if (this.suppressRemoveFlagUpdate) return

      const currentFilesCount = this.pond.getFiles().length

      if (currentFilesCount > 0) {
        this.removeFlagTarget.value = "0"
        return
      }

      this.removeFlagTarget.value = this.hadInitialFile ? "1" : "0"
    })
  }

  loadInitialFile() {
    this.pond.addFile(this.initialUrlValue).catch((error) => {
      if (this.isDisconnected || !this.pond) return

      console.log("[image-upload] initial file load failed", error)
      this.retryInitialFileLoad()
    })
  }

  async retryInitialFileLoad() {
    if (this.initialFileRetryAttempted || this.isDisconnected || !this.pond) return

    this.initialFileRetryAttempted = true
    const retryUrl = this.cacheBustedInitialUrl(this.initialUrlValue)

    console.log("[image-upload] retry initial file load with cache bust", retryUrl)

    await this.removeInitialFileLoadItems(this.initialUrlValue)
    if (this.isDisconnected || !this.pond) return

    this.pond
      .addFile(retryUrl)
      .then(() => {
        if (this.isDisconnected) return

        console.log("[image-upload] retry initial file load succeeded")
      })
      .catch((error) => {
        if (this.isDisconnected) return

        console.log("[image-upload] retry initial file load failed", error)
        this.resetRemoveFlag()
      })
  }

  cacheBustedInitialUrl(url) {
    const cacheBustValue = `${Date.now()}-${Math.random().toString(36).slice(2)}`

    try {
      const parsedUrl = new URL(url, window.location.href)
      parsedUrl.searchParams.set("image_upload_cache_bust", cacheBustValue)

      if (url.startsWith("/") && !url.startsWith("//")) {
        return `${parsedUrl.pathname}${parsedUrl.search}${parsedUrl.hash}`
      }

      return parsedUrl.toString()
    } catch (_) {
      const separator = url.includes("?") ? "&" : "?"
      return `${url}${separator}image_upload_cache_bust=${encodeURIComponent(cacheBustValue)}`
    }
  }

  async removeInitialFileLoadItems(source) {
    if (!this.pond) return

    const initialFiles = this.pond.getFiles().filter((file) => file.source === source)
    if (initialFiles.length === 0) return

    this.suppressRemoveFlagUpdate = true

    try {
      await Promise.allSettled(
        initialFiles.map((file) => {
          try {
            return Promise.resolve(this.pond.removeFile(file.id ?? file, { revert: false }))
          } catch (error) {
            return Promise.reject(error)
          }
        })
      )
    } finally {
      this.suppressRemoveFlagUpdate = false
      this.resetRemoveFlag()
    }
  }

  resetRemoveFlag() {
    if (!this.hasRemoveFlagTarget) return

    this.removeFlagTarget.value = "0"
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
