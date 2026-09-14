import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "error"]
  static values = { url: String }

  disconnect() {
    this.cancel()
  }

  async refresh() {
    this.cancel()
    const request = new AbortController()
    this.request = request
    this.contentTarget.textContent = "共有情報を取得しています…"
    this.errorTarget.hidden = true
    const timer = window.setTimeout(() => request.abort(), 15000)
    try {
      const response = await fetch(this.urlValue, {
        credentials: "same-origin", headers: { Accept: "text/html" }, signal: request.signal
      })
      if (!response.ok || response.redirected) throw new Error("share_unavailable")
      const html = await response.text()
      if (this.request !== request) return
      this.contentTarget.innerHTML = html
    } catch (_error) {
      if (this.request !== request) return
      this.contentTarget.textContent = ""
      this.errorTarget.hidden = false
    } finally {
      window.clearTimeout(timer)
      if (this.request === request) this.request = null
    }
  }

  cancel() {
    this.request?.abort()
    this.request = null
  }
}
