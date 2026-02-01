import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

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
      const res = await fetch(this.pingUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
          "Accept": "application/json"
        }
      }).catch(() => null)

      // ★BANなどで403ならトップへ退避（購読も切れる）
      if (res && res.status === 403) {
        Turbo.visit("/")
        return
      }
    }

    const res2 = await fetch(this.summaryUrlValue, {
      headers: { "Accept": "application/json" }
    }).catch(() => null)

    // ★summary側でも403ならトップへ退避
    if (res2 && res2.status === 403) {
      Turbo.visit("/")
      return
    }

    if (!res2 || !res2.ok) return

    const data = await res2.json()
    this.countTarget.textContent = String(data.viewer_count ?? "-")

    if (typeof data.joinable === "boolean") {
      const next = data.joinable
      if (this._lastJoinable !== next) {
        this._lastJoinable = next
        window.dispatchEvent(
          new CustomEvent("stream-session:joinable", { detail: { joinable: next } })
        )
      }
    }
  }
}
