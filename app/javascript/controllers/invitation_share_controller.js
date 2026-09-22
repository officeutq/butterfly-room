import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "retry"]
  static values = { url: String }

  async record() {
    if (this.busy || this.recorded) return
    this.busy = true
    this.retryTarget.disabled = true
    this.abortController = new AbortController()
    const timeout = window.setTimeout(() => this.abortController.abort(), 15000)
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", credentials: "same-origin", signal: this.abortController.signal,
        headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content }
      })
      if (!response.ok) throw new Error()
      this.recorded = true
      this.statusTarget.textContent = "共有・コピーの完了を記録しました。"
      this.retryTarget.hidden = true
    } catch (_) {
      this.statusTarget.textContent = "共有・コピーは完了しましたが、記録を保存できませんでした。再試行してください。"
      this.retryTarget.hidden = false
    } finally {
      window.clearTimeout(timeout)
      this.busy = false
      this.retryTarget.disabled = false
    }
  }

  disconnect() { this.abortController?.abort() }
}
