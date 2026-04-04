import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  connect() {
    this.modal = null
    this._onHidden = null
    this._redirectTimeout = null
  }

  open() {
    const redirectEl = this.element.querySelector("[data-redirect-url]")
    const redirectUrl = redirectEl?.dataset?.redirectUrl
    const redirectDelay = Number(redirectEl?.dataset?.redirectDelay || 120)

    if (redirectUrl) {
      this._redirectTimeout = window.setTimeout(() => {
        if (window.Turbo && typeof window.Turbo.visit === "function") {
          window.Turbo.visit(redirectUrl)
        } else {
          window.location.assign(redirectUrl)
        }
      }, redirectDelay)
      return
    }

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
      this._clearRedirectTimeout()

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
    this._clearRedirectTimeout()

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
    this._clearRedirectTimeout()

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

  _clearRedirectTimeout() {
    if (this._redirectTimeout) {
      window.clearTimeout(this._redirectTimeout)
      this._redirectTimeout = null
    }
  }

  _cleanupBootstrapModalState() {
    document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove())
    document.body.classList.remove("modal-open")
    document.body.style.removeProperty("padding-right")
    document.body.style.removeProperty("overflow")
  }
}
