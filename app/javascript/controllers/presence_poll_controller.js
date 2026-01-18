import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    pingUrl: String,
    summaryUrl: String,
    intervalMs: Number
  }
  static targets = ["count"]

  connect() {
    this._tick = this._tick.bind(this)
    this._timer = setInterval(this._tick, this.intervalMsValue || 20000)
    this._tick()
  }

  disconnect() {
    if (this._timer) clearInterval(this._timer)
  }

  async _tick() {
    // customer画面だけ pingUrl を渡す（cast画面は渡さない＝書き込み無し）
    if (this.hasPingUrlValue) {
      await fetch(this.pingUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
          "Accept": "application/json"
        }
      }).catch(() => {})
    }

    const res = await fetch(this.summaryUrlValue, { headers: { "Accept": "application/json" } }).catch(() => null)
    if (!res || !res.ok) return

    const data = await res.json()
    this.countTarget.textContent = String(data.viewer_count ?? "-")
  }
}
