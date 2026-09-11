import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // 戻る操作で古いアカウント情報・認証バッジを復元しない。
    window.Turbo.cache.clear()
    const frame = this.element.closest("turbo-frame#modal")
    const form = frame.querySelector("[data-controller~='account-modal-form']")
    if (form) this.application.getControllerForElementAndIdentifier(form, "account-modal-form")?.finish()
    const modal = this.application.getControllerForElementAndIdentifier(frame, "modal")
    if (modal?.opener && !modal.opener.isConnected) {
      const href = modal.opener.getAttribute("href")
      modal.opener = Array.from(document.querySelectorAll(".profile-edit__account a"))
        .find((link) => link.getAttribute("href") === href)
    }
    modal?.close()
  }
}
