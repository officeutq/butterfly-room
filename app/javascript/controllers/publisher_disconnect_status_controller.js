import { Controller } from "@hotwired/stimulus"

// 終了・取消の結果表示だけを更新する。AWS切断や配信継続中の監視は行わない。
export default class extends Controller {
  static values = { url: String, state: String }

  connect() {
    this.operation = {}
    if (this.stateValue === "retrying") void this.readState(0)
  }

  disconnect() {
    this.operation = null
    clearTimeout(this.timer)
    this.abort?.abort()
  }

  async readState(attempt, operation = this.operation) {
    if (!operation || this.operation !== operation) return
    const delays = [500, 1000, 2000]
    const abort = new AbortController()
    this.abort = abort
    const timeout = setTimeout(() => abort.abort(), 15000)
    try {
      const response = await fetch(this.urlValue, { credentials: "same-origin", headers: { Accept: "application/json" }, signal: abort.signal })
      if (!response.ok) throw new Error("publisher_disconnect_state_unavailable")
      const state = await response.json()
      if (this.operation !== operation) return
      if (!["retrying", "failed", "disconnected"].includes(state.disconnect_state)) throw new Error("invalid_disconnect_state")
      this.element.textContent = state.message
      this.element.classList.toggle("d-none", state.disconnect_state === "disconnected")
      this.element.classList.toggle("alert-danger", state.disconnect_state === "failed")
      this.element.classList.toggle("alert-warning", state.disconnect_state !== "failed")
      if (state.disconnect_state !== "retrying") return
    } catch (_) {
      if (this.operation !== operation) return
    } finally {
      clearTimeout(timeout)
    }
    if (attempt < delays.length) {
      this.timer = setTimeout(() => { if (this.operation === operation) void this.readState(attempt + 1, operation) }, delays[attempt])
    } else {
      this.element.textContent = "配信接続の切断結果をまだ確認できません。最新の結果は画面を読み込み直して確認してください。"
    }
  }
}
