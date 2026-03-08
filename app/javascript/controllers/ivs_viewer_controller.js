import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "error", "state", "muteButton", "muteHint"]
  static values = {
    tokenUrl: String, // /stream_sessions/:id/ivs_participant_tokens
  }

  connect() {
    this._stage = null
    this._lastJoinable = null
    this._remoteMediaStream = null
    this._remoteTrackMap = new Map()

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

    // 初期UI
    this._setState("idle")
    this._syncMuteUI({ hint: false })

    // YouTube寄せ：表示されたら自動で視聴開始を試みる
    queueMicrotask(() => this.start())
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
          this._addStreams(streams)
        })
      } else {
        console.warn("[ivs-viewer] StageEvents.STAGE_PARTICIPANT_STREAMS_ADDED is missing")
      }

      const evtRemoved = StageEvents?.STAGE_PARTICIPANT_STREAMS_REMOVED
      if (evtRemoved) {
        this._stage.on(evtRemoved, (_participant, streams) => {
          this._removeStreams(streams)
        })
      }

      await this._stage.join()
      this._setState("joined")
    } catch (e) {
      this._setState("error")
      this._setError(this._humanizeError(e))
      this.stop()
    }
  }

  // 🔇/🔊 トグル（常時表示）
  async toggleMute() {
    if (!this.hasVideoTarget) return
    const v = this.videoTarget

    if (v.muted) {
      // muted -> unmuted（ユーザー操作なので play 再試行する）
      v.muted = false
      try {
        await v.play?.()
        this._syncMuteUI({ hint: false })
      } catch (_) {
        // まだ音が出せない（端末制約など）→ミュートに戻し、ヒントを出す
        v.muted = true
        try { await v.play?.() } catch (_) {}
        this._syncMuteUI({ hint: true })
      }
    } else {
      // unmuted -> muted
      v.muted = true
      this._syncMuteUI({ hint: false })
    }
  }

  stop() {
    try {
      if (this._stage) this._stage.leave()
    } catch (_) {
      // noop
    } finally {
      this._stage = null
      this._remoteTrackMap.clear()
      this._remoteMediaStream = null
      if (this.hasVideoTarget) this.videoTarget.srcObject = null
      this._setState("idle")
      this._syncMuteUI({ hint: false })
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

  async _addStreams(streams) {
    if (!streams?.length) return
    if (!this.hasVideoTarget) return

    if (!this._remoteMediaStream) {
      this._remoteMediaStream = new MediaStream()
    }

    let changed = false

    streams.forEach((stream) => {
      const track = stream?.mediaStreamTrack
      if (!track) return

      const key = this._streamKey(stream, track)
      if (this._remoteTrackMap.has(key)) return

      this._remoteTrackMap.set(key, track)
      this._remoteMediaStream.addTrack(track)
      changed = true
    })

    if (!changed) return

    const v = this.videoTarget
    const currentMuted = v.muted
    v.srcObject = this._remoteMediaStream

    // 1) まず音あり（unmuted autoplay）を試す
    // 2) 失敗したら muted autoplay にフォールバック（映像優先）
    try {
      v.muted = currentMuted ? true : false
      await v.play?.()
      this._syncMuteUI({ hint: false })
    } catch (_) {
      v.muted = true
      try { await v.play?.() } catch (_) {}
      // 音が出ない状態を明示（ユーザー操作で解除できる）
      this._syncMuteUI({ hint: true })
    }
  }

  _removeStreams(streams) {
    if (!streams?.length) return
    if (!this._remoteMediaStream) return

    streams.forEach((stream) => {
      const track = stream?.mediaStreamTrack
      if (!track) return

      const key = this._streamKey(stream, track)
      const existingTrack = this._remoteTrackMap.get(key)
      if (!existingTrack) return

      try {
        this._remoteMediaStream.removeTrack(existingTrack)
      } catch (_) {}

      this._remoteTrackMap.delete(key)
    })
  }

  _streamKey(stream, track) {
    return String(stream?.id || track?.id || Math.random())
  }

  _syncMuteUI(opts = {}) {
    const { hint = false } = opts
    if (!this.hasVideoTarget) return
    const v = this.videoTarget

    if (this.hasMuteButtonTarget) {
      // muted=true なら「🔇」、muted=false なら「🔊」
      this.muteButtonTarget.textContent = v.muted ? "🔇" : "🔊"
    }

    if (this.hasMuteHintTarget) {
      // ヒントは「音が出ない（=mutedで視聴している）」時だけ、必要に応じて表示
      const show = hint && v.muted
      this.muteHintTarget.style.display = show ? "" : "none"
    }
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
