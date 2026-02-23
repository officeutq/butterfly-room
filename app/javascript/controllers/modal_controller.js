import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  connect() {
    this.modal = null
    this._onHidden = null
  }

  open() {
    // turbo-frame(#modal) の中に modal 断片が入った時だけ開く
    const modalEl = this.element.querySelector(".modal")
    if (!modalEl) return

    // 既に開いている/残骸がある場合は破棄してから作り直す（連打耐性）
    if (this.modal) {
      try { this.modal.hide() } catch (_) {}
      try { this.modal.dispose() } catch (_) {}
      this.modal = null
    }

    this.modal = new Modal(modalEl, {
      backdrop: "static",
      keyboard: true
    })

    // 閉じたら frame を空に戻す（次回のため）
    this._onHidden = () => {
      // dispose してからDOMを消す
      try { this.modal?.dispose() } catch (_) {}
      this.modal = null
      this.element.innerHTML = ""
      this._onHidden = null
    }

    modalEl.addEventListener("hidden.bs.modal", this._onHidden, { once: true })
    this.modal.show()
  }

  disconnect() {
    // Turboのキャッシュ/遷移で disconnect されるケースに備える
    const modalEl = this.element.querySelector(".modal")

    if (modalEl && this._onHidden) {
      try { modalEl.removeEventListener("hidden.bs.modal", this._onHidden) } catch (_) {}
    }

    if (this.modal) {
      try { this.modal.dispose() } catch (_) {}
      this.modal = null
    }
    this._onHidden = null
  }
}
