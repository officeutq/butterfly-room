import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "error", "state"]
  static values = {
    tokenUrl: String, // /stream_sessions/:id/ivs_participant_tokens
    role: { type: String, default: "publisher" },
    mirror: { type: Boolean, default: true },
  }

  connect() {
    this._stage = null
    this._stream = null
    this._state = "idle" // idle | starting | live | stopping | error
    this._debug = this._isDebugIvs()

    this._beforeCache = () => this.stop()
    document.addEventListener("turbo:before-cache", this._beforeCache)

    if (this.mirrorValue) {
      this.previewTarget.style.transform = "scaleX(-1)"
    }
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this._beforeCache)
    this.stop()
  }

  async start() {
    if (this._state === "starting" || this._state === "live") return
    this._setState("starting")
    this._clearError()

    try {
      // ------------------------------------------------------------
      // debug: skip getUserMedia / publish（デバイス競合回避）
      // ?debug_ivs=1&skip_media=1 のときだけ発動
      // ------------------------------------------------------------
      if (this._debug && this._shouldSkipMedia()) {
        const token = await this._fetchParticipantToken()

        const { Stage, SubscribeType, StageEvents } = window.IVSBroadcastClient || {}
        if (!Stage) throw new Error("IVS SDK not loaded (IVSBroadcastClient is missing)")

        const strategy = {
          stageStreamsToPublish: () => [],
          shouldPublishParticipant: () => false,
          shouldSubscribeToParticipant: () => SubscribeType.NONE,
        }

        this._stage = new Stage(token, strategy)

        // 状態確認（join 成功/失敗の見える化）
        if (StageEvents?.STAGE_CONNECTION_STATE_CHANGED) {
          this._stage.on(StageEvents.STAGE_CONNECTION_STATE_CHANGED, (state) => {
            console.log("[ivs] connection state:", state)
            this._setState(String(state))
          })
        }

        await this._stage.join()
        this._setState("joined(no-media)")
        return
      }

      this._stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user" },
        audio: true,
      })

      // preview（ミラーは video 要素だけ）
      this.previewTarget.srcObject = this._stream
      try { await this.previewTarget.play() } catch (_) {}

      const token = await this._fetchParticipantToken()

      // SDK はグローバルから取る（script tag 読み込み前提）
      const {
        Stage,
        LocalStageStream,
        SubscribeType,
        StageEvents,
      } = window.IVSBroadcastClient || {}

      if (!Stage) throw new Error("IVS SDK not loaded (IVSBroadcastClient is missing)")

      const streamsToPublish = this._stream.getTracks().map((t) => new LocalStageStream(t))

      const strategy = {
        stageStreamsToPublish: () => streamsToPublish,
        shouldPublishParticipant: () => true,
        shouldSubscribeToParticipant: () => SubscribeType.NONE, // ← publisherは受信しない
      }

      this._stage = new Stage(token, strategy)

      // ★ここが join 前（イベント購読を仕込む）
      this._setState("joining")

      if (StageEvents?.STAGE_CONNECTION_STATE_CHANGED) {
        this._stage.on(StageEvents.STAGE_CONNECTION_STATE_CHANGED, (state) => {
          console.log("[ivs] connection state:", state)
          this._setState(String(state))
        })
      }

      await this._stage.join()

      // ★ここが join 後（join()が返ったら一旦成功）
      this._setState("joined")

      // 既存の live 表示があるなら、joined の代わりに live にしてもOK
      // this._setState("live")
    } catch (e) {
      this._setState("error")
      this._setError(this._humanizeError(e))
      this._cleanupStage()
      this._cleanupMedia()
    }
  }

  async stop() {
    if (this._state === "stopping" || this._state === "idle") return
    this._setState("stopping")

    try {
      if (this._stage) {
        // join 失敗でも leave を呼ぶと例外になることがあるのでガード
        this._stage.leave()
      }
    } catch (_) {
      // 失敗しても後片付け優先
    } finally {
      this._cleanupStage()
      this._cleanupMedia()
      this._clearError()
      this._setState("idle")
    }
  }

  async _fetchParticipantToken() {
    const resp = await fetch(this.tokenUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ role: this.roleValue }),
    })

    let body = null
    try { body = await resp.json() } catch (_) {}

    if (!resp.ok) {
      throw new Error(`token_api_failed(${resp.status}) ${body?.error || ""}`.trim())
    }

    return body.participant_token
  }

  _cleanupStage() {
    this._stage = null
  }

  _cleanupMedia() {
    if (this.previewTarget?.srcObject) this.previewTarget.srcObject = null

    if (this._stream) {
      this._stream.getTracks().forEach((t) => t.stop())
      this._stream = null
    }
  }

  _isDebugIvs() {
    try {
      const params = new URLSearchParams(window.location.search || "")
      return params.get("debug_ivs") === "1"
    } catch (_) {
      return false
    }
  }

  _shouldSkipMedia() {
    // debug_ivs=1 のときだけ、さらに skip_media=1 が付いていれば skip
    try {
      const params = new URLSearchParams(window.location.search || "")
      return params.get("skip_media") === "1"
    } catch (_) {
      return false
    }
  }

  _setState(s) {
    this._state = s
    if (this.hasStateTarget) this.stateTarget.textContent = s
  }

  _clearError() {
    if (this.hasErrorTarget) this.errorTarget.textContent = ""
  }

  _setError(msg) {
    if (this.hasErrorTarget) this.errorTarget.textContent = msg
  }

  _humanizeError(err) {
    const msg = `${err?.message || err}`

    // token API 系
    if (msg.includes("token_api_failed(403)")) {
      // フェーズ1: “担当キャストのみ”で弾かれる場合もここに入る
      return "このブースの配信者ではありません（担当キャストのみ配信できます）。"
    }
    if (msg.includes("token_api_failed(409)")) {
      return "まだ配信開始できない状態です（配信状態/ステージ準備を確認）。"
    }
    if (msg.includes("not loaded")) {
      return "IVS SDK の読み込みに失敗しました（script tag を確認してください）。"
    }

    // getUserMedia 系
    if (err?.name === "NotAllowedError" || err?.name === "SecurityError") {
      return "カメラ/マイク権限が拒否されました。ブラウザ設定で許可してください。"
    }
    if (err?.name === "NotFoundError" || err?.name === "OverconstrainedError") {
      return "利用できるカメラ/マイクが見つかりません。接続やOS設定を確認してください。"
    }
    if (err?.name === "NotReadableError") {
      return "カメラ/マイクを使用できません（他アプリ使用中の可能性）。"
    }

    return `配信開始に失敗しました: ${msg}`
  }
}
