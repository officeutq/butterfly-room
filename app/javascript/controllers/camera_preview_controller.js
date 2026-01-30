import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "error"]
  static values = {
    status: String,  // "offline" | "live" | "away"
    active: Boolean, // live/away のとき true
  }

  connect() {
    this.stream = null

    // Turboの戻る/キャッシュ対策：キャッシュ前に必ず解放
    this._beforeCache = () => this.stop()
    document.addEventListener("turbo:before-cache", this._beforeCache)

    if (this.statusValue === "offline") return
    if (this.activeValue) this.start()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this._beforeCache)
    this.stop()
  }

  async start() {
    this._clearError()

    if (this.stream) return

    // offline では開始しない（二重ガード）
    if (this.statusValue === "offline") {
      this._setError("未配信（offline）のため、プレビューは開始しません。")
      return
    }

    if (!navigator.mediaDevices?.getUserMedia) {
      this._setError("このブラウザはカメラ取得（getUserMedia）に対応していません。")
      return
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user" },
        audio: false,
      })

      this.stream = stream
      this.videoTarget.srcObject = stream

      // autoplayがブロックされる場合があるので一応試す
      try {
        await this.videoTarget.play()
      } catch (_) {}
    } catch (err) {
      this._setError(this._humanizeError(err))
      this.videoTarget.srcObject = null
      this.stream = null
    }
  }

  stop() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop())
      this.stream = null
    }
    if (this.hasVideoTarget) this.videoTarget.srcObject = null
  }

  _clearError() {
    if (this.hasErrorTarget) this.errorTarget.textContent = ""
  }

  _setError(message) {
    if (this.hasErrorTarget) this.errorTarget.textContent = message
  }

  _humanizeError(err) {
    switch (err?.name) {
      case "NotAllowedError":
      case "SecurityError":
        return "カメラ権限が拒否されました。ブラウザの権限設定でカメラを許可してください。"
      case "NotFoundError":
      case "OverconstrainedError":
        return "利用できるカメラが見つかりません。カメラ接続・OS設定を確認してください。"
      case "NotReadableError":
        return "カメラを使用できません（他のアプリが使用中の可能性）。他アプリを閉じて再試行してください。"
      default:
        return `カメラ取得に失敗しました。(${err?.name || "UnknownError"})`
    }
  }
}
