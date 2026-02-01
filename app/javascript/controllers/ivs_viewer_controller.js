import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "error", "state"]
  static values = {
    tokenUrl: String, // /stream_sessions/:id/ivs_participant_tokens
  }

  connect() {
    this._stage = null
    this._lastJoinable = null

    this._beforeCache = () => this.stop()
    document.addEventListener("turbo:before-cache", this._beforeCache)

    this._onJoinable = (e) => {
      if (e?.detail?.joinable === false) {
        // Rails状態が正：joinable=false なら viewer を止める
        this._setError("配信が終了しました")
        this.stop()
      }
    }
    window.addEventListener("stream-session:joinable", this._onJoinable)

    this._setState("idle")
  }

  disconnect() {
    window.removeEventListener("stream-session:joinable", this._onJoinable)
    document.removeEventListener("turbo:before-cache", this._beforeCache)
    this.stop()
  }

  async start() {
    if (this._stage) return
    this._clearError()
    this._setState("starting")

    try {
      const token = await this._fetchToken()

      const { Stage, SubscribeType, StageEvents } = window.IVSBroadcastClient || {}
      if (!Stage) throw new Error("IVS SDK not loaded (IVSBroadcastClient is missing)")

      // viewer は購読のみ
      const strategy = {
        stageStreamsToPublish: () => [],
        shouldPublishParticipant: () => false,
        shouldSubscribeToParticipant: () => SubscribeType.AUDIO_VIDEO,
      }

      this._stage = new Stage(token, strategy)

      // 接続状態ログ（存在するときだけ）
      const evtConn = StageEvents?.STAGE_CONNECTION_STATE_CHANGED
      if (evtConn) {
        this._stage.on(evtConn, (state) => {
          console.log("[ivs-viewer] connection state:", state)
          this._setState(String(state))
        })
      }

      // 受信トラック（存在するときだけ）
      const evtAdded = StageEvents?.STAGE_PARTICIPANT_STREAMS_ADDED
      if (evtAdded) {
        this._stage.on(evtAdded, (_participant, streams) => {
          const tracks = streams.flatMap((s) => (s.mediaStreamTrack ? [s.mediaStreamTrack] : []))
          this._attachTracks(tracks)
        })
      } else {
        console.warn("[ivs-viewer] StageEvents.STAGE_PARTICIPANT_STREAMS_ADDED is missing")
      }

      await this._stage.join()
      this._setState("joined")
    } catch (e) {
      this._setState("error")
      this._setError(this._humanizeError(e))
      this.stop()
    }
  }

  stop() {
    try {
      if (this._stage) this._stage.leave()
    } catch (_) {
      // noop
    } finally {
      this._stage = null
      if (this.hasVideoTarget) this.videoTarget.srcObject = null
      this._setState("idle")
    }
  }

  async _fetchToken() {
    const resp = await fetch(this.tokenUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ role: "viewer" }),
    })

    let body = null
    try { body = await resp.json() } catch (_) {}

    if (!resp.ok) throw new Error(`token_api_failed(${resp.status}) ${body?.error || ""}`.trim())
    return body.participant_token
  }

  _attachTracks(tracks) {
    if (!tracks.length) return
    if (!this.hasVideoTarget) return

    // フェーズ1：1キャスト前提なので「毎回上書き」でOK
    const ms = new MediaStream()
    tracks.forEach((t) => ms.addTrack(t))

    this.videoTarget.srcObject = ms
    this.videoTarget.play?.().catch(() => {})
  }

  _setState(s) {
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
    if (msg.includes("token_api_failed(403)")) return "視聴権限がありません（forbidden）"
    if (msg.includes("token_api_failed(409)")) return "視聴できない状態です（配信中か確認）"
    if (msg.includes("IVS SDK not loaded")) return "IVS SDK の読み込みに失敗しました（script tag を確認してください）。"
    return `視聴開始に失敗しました: ${msg}`
  }
}
