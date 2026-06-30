import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "placeholder", "removeFlag", "uploadTile"]

  connect() {
    this.previewObjectUrl = null
  }

  disconnect() {
    this.revokePreviewObjectUrl()
  }

  open(event) {
    event.preventDefault()
    if (!this.hasInputTarget) return

    this.inputTarget.click()
  }

  preview() {
    if (!this.hasInputTarget || !this.inputTarget.files.length) return

    const file = this.inputTarget.files[0]
    this.revokePreviewObjectUrl()
    this.previewObjectUrl = URL.createObjectURL(file)

    if (this.hasPreviewTarget) {
      this.previewTarget.src = this.previewObjectUrl
      this.previewTarget.classList.remove("d-none")
    }

    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.classList.add("d-none")
    }

    if (this.hasRemoveFlagTarget) {
      this.removeFlagTarget.value = "0"
    }

    if (this.hasUploadTileTarget) {
      this.uploadTileTarget.classList.add("is-custom-selected")
    }
  }

  selectPreset() {
    this.clearInput()

    if (this.hasRemoveFlagTarget) {
      this.removeFlagTarget.value = "1"
    }

    if (this.hasPreviewTarget) {
      this.previewTarget.removeAttribute("src")
      this.previewTarget.classList.add("d-none")
    }

    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.classList.remove("d-none")
    }

    if (this.hasUploadTileTarget) {
      this.uploadTileTarget.classList.remove("is-custom-selected")
    }
  }

  clearInput() {
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
    }

    this.revokePreviewObjectUrl()
  }

  revokePreviewObjectUrl() {
    if (!this.previewObjectUrl) return

    URL.revokeObjectURL(this.previewObjectUrl)
    this.previewObjectUrl = null
  }
}
