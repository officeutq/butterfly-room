import { Controller } from "@hotwired/stimulus"

const ACCEPTED_FILE_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
]
const CONTENT_TYPE_BY_EXTENSION = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  heic: "image/heic",
  heif: "image/heif",
}
const FILEPOND_PLUGIN_GLOBALS = [
  "FilePondPluginFileValidateType",
  "FilePondPluginImagePreview",
  "FilePondPluginImageResize",
  "FilePondPluginImageTransform",
]
const MAX_SETUP_ATTEMPTS = 40
const SETUP_RETRY_INTERVAL_MS = 50

export default class extends Controller {
  static targets = ["input", "removeFlag", "error"]
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
    this.setupTimer = null

    this.scheduleSetup(0)
  }

  disconnect() {
    this.isDisconnected = true
    if (this.setupTimer) {
      clearTimeout(this.setupTimer)
      this.setupTimer = null
    }
    if (this.pond) {
      this.pond.destroy()
      this.pond = null
    }
  }

  setupFilePond() {
    this.setupTimer = null
    if (this.isDisconnected) return
    if (this.pond) return
    if (!this.hasInputTarget) return

    if (!this.filePondReady()) {
      if (this.setupAttempts >= MAX_SETUP_ATTEMPTS) return

      this.setupAttempts += 1
      this.scheduleSetup(SETUP_RETRY_INTERVAL_MS)
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

      // クライアント変換は通信量削減とプレビューの補助であり、保存形式はサーバー側で保証する。
      // ブラウザがHEIC/HEIFを変換できない場合は原本が送信され、サーバー側でJPEGへ正規化される。
      imageTransformOutputMimeType: "image/jpeg",
      imageTransformOutputQuality: 94,
      imageTransformCanvasBackgroundColor: "#ffffff",

      acceptedFileTypes: ACCEPTED_FILE_TYPES,
      labelFileTypeNotAllowed: "対応していない画像形式です",
      fileValidateTypeLabelExpectedTypes:
        "JPEG / PNG / WebP / HEIC / HEIFを選択してください",
      fileValidateTypeDetectType: (file, browserType) =>
        Promise.resolve(this.detectFileType(file, browserType)),

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

  scheduleSetup(delay) {
    if (this.isDisconnected) return

    this.setupTimer = setTimeout(() => {
      this.setupFilePond()
    }, delay)
  }

  filePondReady() {
    return (
      window.FilePond &&
      FILEPOND_PLUGIN_GLOBALS.every((pluginName) => window[pluginName])
    )
  }

  detectFileType(file, browserType) {
    const normalizedBrowserType = browserType?.toLowerCase() || ""
    if (normalizedBrowserType && normalizedBrowserType !== "application/octet-stream") {
      return normalizedBrowserType
    }

    const filename = file?.name || ""
    const extension = filename.split(".").pop()?.toLowerCase()

    return CONTENT_TYPE_BY_EXTENSION[extension] || normalizedBrowserType
  }

  bindEvents() {
    this.pond.on("addfile", (error, _file, status) => {
      if (error) {
        this.showInputError(status || error)
        return
      }

      this.clearInputError()
      this.removeFlagTarget.value = "0"
    })

    this.pond.on("removefile", () => {
      if (this.suppressRemoveFlagUpdate) return

      this.clearInputError()
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

        this.clearInputError()
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

  showInputError(error) {
    if (!this.hasErrorTarget) return

    const message = [error?.main, error?.sub].filter(Boolean).join(" ")
    this.errorTarget.textContent =
      message || "画像を読み込めませんでした。別の画像を選択してください"
    this.errorTarget.hidden = false
  }

  clearInputError() {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }

  registerPlugins() {
    if (window.__filepondRegistered) return

    const plugins = FILEPOND_PLUGIN_GLOBALS.map((pluginName) => window[pluginName])

    plugins.forEach((plugin) => {
      window.FilePond.registerPlugin(plugin)
    })

    window.__filepondRegistered = true
  }
}
