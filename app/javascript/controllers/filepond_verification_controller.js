import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.initializeFilePond()
  }

  disconnect() {
    this.destroyFilePond()
  }

  initializeFilePond() {
    if (!this.hasInputTarget) return
    if (!window.FilePond) {
      console.error("[filepond-verification] FilePond is not loaded")
      return
    }

    this.registerPlugins()

    this.pond = window.FilePond.create(this.inputTarget, {
      storeAsFile: true,
      allowMultiple: false,
      allowReorder: false,
      allowProcess: false,
      allowRevert: false,
      allowImagePreview: true,
      allowImageResize: true,
      allowImageTransform: true,
      imageResizeTargetWidth: 1920,
      imageResizeTargetHeight: 1080,
      imageResizeMode: "contain",
      imageResizeUpscale: false,
      imageTransformOutputMimeType: "image/jpeg",
      imageTransformOutputQuality: 94,
      imageTransformCanvasBackgroundColor: "#ffffff",
      labelIdle:
        '画像をドラッグ＆ドロップするか <span class="filepond--label-action">参照</span>',
    })
  }

  destroyFilePond() {
    if (!this.pond) return

    this.pond.destroy()
    this.pond = null
  }

  registerPlugins() {
    if (window.__filepondVerificationPluginsRegistered) return

    const plugins = [
      window.FilePondPluginImagePreview,
      window.FilePondPluginImageResize,
      window.FilePondPluginImageTransform,
    ].filter(Boolean)

    plugins.forEach((plugin) => {
      window.FilePond.registerPlugin(plugin)
    })

    window.__filepondVerificationPluginsRegistered = true
  }
}
