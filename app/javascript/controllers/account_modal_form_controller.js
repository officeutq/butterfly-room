import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["error"]

  start() {
    this.sending = true
    this.errorTarget.hidden = true
    this.element.setAttribute("aria-busy", "true")
    // Turboが管理する送信元ボタンを除き、再送・閉じる等の同時操作を止める。
    this.disabledButtons = Array.from(this.element.querySelectorAll("button:not([disabled]), input[type='submit']:not([disabled])"))
    this.disabledButtons.forEach((button) => { button.disabled = true })
  }

  finish() {
    this.sending = false
    this.element.removeAttribute("aria-busy")
    this.disabledButtons?.forEach((button) => { button.disabled = false })
    this.disabledButtons = []
  }

  failed(event) {
    event.preventDefault()
    this.finish()
    this.errorTarget.textContent = "通信に失敗しました。入力内容を確認して、もう一度お試しください。"
    this.errorTarget.hidden = false
  }

  beforeClose(event) {
    if (this.sending) event.preventDefault()
  }

  beforeNavigate(event) {
    if (this.sending && event.target.closest("a")) event.preventDefault()
  }
}
