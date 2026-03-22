import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "openButton", "frame"]
  static values = {
    loaded: { type: Boolean, default: false },
    menuUrl: String,
  }

  connect() {
    this.isOpen = false

    this._onKeydown = (event) => {
      if (event.key === "Escape") {
        this.close()
      }
    }

    document.addEventListener("keydown", this._onKeydown)
    this._sync()
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  toggle(event) {
    event?.preventDefault()
    this.isOpen ? this.close() : this.open()
  }

  open(event) {
    event?.preventDefault()
    this._ensureFrameLoaded()
    this.isOpen = true
    this._sync()
  }

  close(event) {
    event?.preventDefault()
    this.isOpen = false
    this._sync()
  }

  closeOnBackdrop(event) {
    if (event.target !== event.currentTarget) return
    this.close()
  }

  _ensureFrameLoaded() {
    if (!this.hasFrameTarget) return
    if (!this.hasMenuUrlValue) return
    if (this.loadedValue) return

    this.frameTarget.setAttribute("src", this.menuUrlValue)
    this.loadedValue = true
  }

  _sync() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.toggle("d-none", !this.isOpen)
      this.overlayTarget.setAttribute("aria-hidden", this.isOpen ? "false" : "true")
    }

    if (this.hasOpenButtonTarget) {
      this.openButtonTarget.classList.toggle("is-active", this.isOpen)
      this.openButtonTarget.setAttribute("aria-expanded", this.isOpen ? "true" : "false")
    }
  }
}
