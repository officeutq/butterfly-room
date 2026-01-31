import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "error", "state"]
  static values = {
    tokenUrl: String, // /stream_sessions/:id/ivs_participant_tokens
  }

  connect() {
    this._stage = null
    this._beforeCache = () => this.stop()
    document.addEventListener("turbo:before-cache", this._beforeCache)
    this._setState("idle")
  }

  disconnect() {
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

      // 接続状態ログ
      if (StageEvents?.STAGE_CONNECTION_STATE_CHANGED) {
        this._stage.on(StageEvents.STAGE_CONNECTION_STATE_CHANGED, (state) => {
          console.log("[ivs-viewer] connection state:", state)
          this._setState(String(state))
        })
      }

      // 受信した MediaStreamTrack を video に流す
      // ※ イベント名は SDK バージョンで差が出ることがあるので、
      //   まずは “参加者/ストリームが追加されたら track を拾う” だけに寄せる
      this._stage.on(StageEvents?.STAGE_PARTICIPANT_STREAMS_ADDED, (participant, streams) => {
        const tracks = streams.flatMap((s) => (s.mediaStreamTrack ? [s.mediaStreamTrack] : []))
        this._attachTracks(tracks)
      })

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

    // track から MediaStream を作って video に流す
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
    return `視聴開始に失敗しました: ${msg}`
  }
}
