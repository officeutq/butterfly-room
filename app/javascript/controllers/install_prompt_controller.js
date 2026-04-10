import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  static targets = ["modal", "safariOnly", "genericOnly"]

  connect() {
    if (!this.shouldShowPrompt()) {
      this.element.remove()
      return
    }

    this.updateBrowserSpecificContent()
    this.modal = this.hasModalTarget ? new Modal(this.modalTarget) : null
  }

  disconnect() {
    if (this.modal) {
      try {
        this.modal.dispose()
      } catch (_) {}
      this.modal = null
    }

    document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove())
    document.body.classList.remove("modal-open")
    document.body.style.removeProperty("padding-right")
    document.body.style.removeProperty("overflow")
  }

  openModal() {
    this.modal?.show()
  }

  closeModal() {
    this.modal?.hide()
  }

  shouldShowPrompt() {
    if (this.isStandalone()) return false

    const coarse = window.matchMedia("(pointer: coarse)").matches
    const noHover = window.matchMedia("(hover: none)").matches
    const tabletOrSmaller = window.matchMedia("(max-width: 1024px)").matches

    return tabletOrSmaller && (coarse || noHover)
  }

  updateBrowserSpecificContent() {
    const safari = this.isSafari()

    this.safariOnlyTargets.forEach((element) => {
      element.hidden = !safari
    })

    this.genericOnlyTargets.forEach((element) => {
      element.hidden = safari
    })
  }

  isStandalone() {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true
    )
  }

  isSafari() {
    const ua = window.navigator.userAgent
    const isIos = /iPhone|iPad|iPod/.test(ua)
    const hasSafari = /Safari/.test(ua)
    const excluded = /CriOS|FxiOS|EdgiOS|OPiOS/.test(ua)

    return isIos && hasSafari && !excluded
  }
}
