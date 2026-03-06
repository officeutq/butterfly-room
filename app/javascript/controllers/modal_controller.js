import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  connect() {
    this.modal = null
    this._onHidden = null
  }

  open() {
    const modalEl = this.element.querySelector(".modal")
    if (!modalEl) return

    if (this.modal) {
      try { this.modal.dispose() } catch (_) {}
      this.modal = null
    }

    this.modal = new Modal(modalEl, {
      backdrop: "static",
      keyboard: true
    })

    this._onHidden = () => {
      try { this.modal?.dispose() } catch (_) {}
      this.modal = null
      this.element.innerHTML = ""
      this._onHidden = null
      this._cleanupBootstrapModalState()
    }

    modalEl.addEventListener("hidden.bs.modal", this._onHidden, { once: true })
    this.modal.show()
  }

  submitEnd(event) {
    if (!event?.detail?.success) return
    this.close()
  }

  close() {
    if (this.modal) {
      try {
        this.modal.hide()
        return
      } catch (_) {
        try { this.modal.dispose() } catch (_) {}
        this.modal = null
      }
    }

    this.element.innerHTML = ""
    this._cleanupBootstrapModalState()
  }

  disconnect() {
    const modalEl = this.element.querySelector(".modal")

    if (modalEl && this._onHidden) {
      try { modalEl.removeEventListener("hidden.bs.modal", this._onHidden) } catch (_) {}
    }

    if (this.modal) {
      try { this.modal.dispose() } catch (_) {}
      this.modal = null
    }

    this._onHidden = null
    this._cleanupBootstrapModalState()
  }

  _cleanupBootstrapModalState() {
    document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove())
    document.body.classList.remove("modal-open")
    document.body.style.removeProperty("padding-right")
    document.body.style.removeProperty("overflow")
  }
}
