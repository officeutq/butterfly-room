import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "removeFlag"]

  connect() {
    this.initialize()
  }

  disconnect() {
    if (this.pond) this.pond.destroy()
  }

  initialize() {
    if (!window.FilePond) return

    this.registerPlugins()

    this.pond = window.FilePond.create(this.inputTarget, {
      storeAsFile: true,
      allowMultiple: false,
      allowImagePreview: true,
      allowImageResize: true,
      allowImageTransform: true,

      imageResizeTargetWidth: 1024,
      imageResizeTargetHeight: 1024,
      imageResizeMode: "contain",
      imageResizeUpscale: false,

      imageTransformOutputMimeType: "image/jpeg",
      imageTransformOutputQuality: 94,

      acceptedFileTypes: [
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
      ],

      labelIdle: `
        <div class="profile-avatar-picker">
          <i class="bi bi-camera-fill profile-avatar-picker__icon" aria-hidden="true"></i>
        </div>
      `,
    })

    this.bindEvents()
  }

  bindEvents() {
    this.pond.on("addfile", () => {
      this.removeFlagTarget.value = "0"
    })

    this.pond.on("removefile", () => {
      this.removeFlagTarget.value = "1"
    })
  }

  registerPlugins() {
    if (window.__filepondRegistered) return

    const plugins = [
      window.FilePondPluginImagePreview,
      window.FilePondPluginImageResize,
      window.FilePondPluginImageTransform,
    ].filter(Boolean)

    plugins.forEach((p) => window.FilePond.registerPlugin(p))
    window.__filepondRegistered = true
  }
}
