import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "error"]
  static values = { storeId: Number, url: String }

  changed(event) {
    if (event.detail?.storeId === this.storeIdValue) this.needsRefresh = true
  }

  async refresh() {
    if (!this.needsRefresh || this.loading) return
    this.loading = true
    this.abortController = new AbortController()
    const timeout = window.setTimeout(() => this.abortController.abort(), 15000)
    try {
      const response = await fetch(this.urlValue, { credentials: "same-origin", signal: this.abortController.signal })
      if (!response.ok) throw new Error()
      const page = new DOMParser().parseFromString(await response.text(), "text/html")
      const content = page.querySelector("#store_invitation_list [data-invitation-list-target='content']")
      if (!content) throw new Error()
      this.contentTarget.replaceChildren(...content.childNodes)
      this.errorTarget.hidden = true
      this.needsRefresh = false
      window.Turbo?.cache.clear()
    } catch (_) {
      if (!this.element.isConnected) return
      this.errorTarget.textContent = "一覧を更新できませんでした。選択店舗を確認し、このタブを開き直してください。"
      this.errorTarget.hidden = false
    } finally {
      window.clearTimeout(timeout)
      this.loading = false
    }
  }

  disconnect() { this.abortController?.abort() }
}
