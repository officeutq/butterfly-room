import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "canvas", "error", "state", "awayAudio", "startBtn", "endBtn", "awayBtn", "backBtn", "summaryBtn"]
  static values = {
    tokenUrl: String,
    finishUrl: String,
    statusUrl: String,
    mirror: { type: Boolean, default: true },
    initialMode: { type: String, default: "normal" },
    initialBoothStatus: String, // "offline" | "live" | "away" | "standby" etc
  }

  connect() {
    this._stage = null
    this._media = null // getUserMedia result
    this._audioTrack = null
    this._canvasStream = null
    this._state = "idle"
    this._mode = this.initialModeValue === "away" ? "away" : "normal"
    this._raf = null

    // before-cache でフラグを立ててから片付ける
    this._beforeCache = () => {
      // 配信中（=join済み）だったら「復帰候補」を残す
      if (this._broadcasting) {
        sessionStorage.setItem(this._resumeKey(), "1")
      }
      this.endBroadcast({ skipFinish: true })
    }
    document.addEventListener("turbo:before-cache", this._beforeCache)

    if (this.mirrorValue) {
      this.previewTarget.style.transform = "scaleX(-1)"
    }

    // 初期状態に合わせてUI
    this._syncAwayAudioUI()
    this._setState("idle")
    this._boothStatus = this.initialBoothStatusValue || "offline" // 画面の初期
    this._broadcasting = false // stage join 済みか

    // ★ boothが live/away なら常に復帰候補
    this._resumable =
      (this._boothStatus === "live" || this._boothStatus === "away")
    this._syncUI()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this._beforeCache)
    // ★配信中に離脱したなら「復帰」候補を残す（finishはしない）
    if (this._broadcasting) {
      sessionStorage.setItem(this._resumeKey(), "1")
    }
    // サーバのfinishはしないが、Stageは確実に離脱する
    try {
      if (this._stage) this._stage.leave()
    } catch (_) {}
    this._cleanupStage()
    this._cleanupMediaAndCanvas()
  }

  // -------------------------
  // 2トグル：配信開始/配信終了
  // -------------------------
  async startBroadcast() {
    if (this._stage) return
    if (!this.hasTokenUrlValue) {
      this._setError("スタンバイを開始してください（配信セッションがありません）。")
      return
    }
    this._clearError()
    this._setState("starting")

    try {
      // 1) getUserMedia（preview用 + audio用）
      this._media = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user" },
        audio: true,
      })

      // preview（ミラーは video 要素だけ）
      this.previewTarget.srcObject = this._media
      try { await this.previewTarget.play() } catch (_) {}

      // 2) publisher token
      const token = await this._fetchParticipantToken("publisher")

      // 3) canvas描画ループ開始
      this._startCanvasRenderLoop()

      // 4) canvas 1本 publish（videoTrackはcanvas、audioはgetUserMedia）
      const { Stage, LocalStageStream, SubscribeType, StageEvents } = window.IVSBroadcastClient || {}
      if (!Stage) throw new Error("IVS SDK not loaded (IVSBroadcastClient is missing)")

      this._canvasStream = this.canvasTarget.captureStream(30)
      const canvasVideoTrack = this._canvasStream.getVideoTracks()[0]
      this._audioTrack = this._media.getAudioTracks()[0] || null

      const streamsToPublish = []
      if (canvasVideoTrack) streamsToPublish.push(new LocalStageStream(canvasVideoTrack))
      if (this._audioTrack) streamsToPublish.push(new LocalStageStream(this._audioTrack))

      const strategy = {
        stageStreamsToPublish: () => streamsToPublish,
        shouldPublishParticipant: () => true,
        shouldSubscribeToParticipant: () => SubscribeType.NONE,
      }

      this._stage = new Stage(token, strategy)

      if (StageEvents?.STAGE_CONNECTION_STATE_CHANGED) {
        this._stage.on(StageEvents.STAGE_CONNECTION_STATE_CHANGED, (state) => {
          console.log("[ivs] connection state:", state)
          this._setState(String(state))
        })
      }

      this._setState("joining")
      await this._stage.join()
      this._setState("live")

      this._broadcasting = true
      this._syncUI()

      // 5) Rails側を live に揃える（standby -> live）
      await this._patchBoothStatus("live")
      this._boothStatus = "live"
      this._syncUI()

      // 6) 現在モードに応じて away の音声デフォルトミュート
      if (this._mode === "away") this._applyAwayMode()
      else this._applyNormalMode()
    } catch (e) {
      this._setState("error")
      this._setError(this._humanizeError(e))
      this._cleanupStage()
      this._cleanupMediaAndCanvas()
    }
    this._syncUI()
  }

  /**
   * 配信終了（Issue #78: 即サマリーへ）
   * - Stage leave
   * - media stop
   * - Rails finish を叩く（skipFinish=true のときは叩かない）
   */
  async endBroadcast(opts = {}) {
    const { skipFinish = false } = opts
    this._setState("stopping")

    try {
      if (this._stage) {
        try { this._stage.leave() } catch (_) {}
      }
    } finally {
      this._cleanupStage()
      this._cleanupMediaAndCanvas()
      this._clearError()
      this._setState("idle")
      this._broadcasting = false
      this._syncUI()

      if (!skipFinish && this.finishUrlValue) {
        // Rails: stream_session finish（booth.offline + current_session解除 + ended broadcast）
        await this._postFinish()
        // Turbo Driveのままならページはそのままなので、UIはボタン側がサマリーに寄る
        // （必要なら location.reload() でもOK）
        window.location.reload()
      }
    }
  }

  setAway() {
    this._mode = "away"
    this._applyAwayMode()
  }

  setLive() {
    this._mode = "normal"
    this._applyNormalMode()
  }

  toggleAwayAudio() {
    if (!this._audioTrack) return
    // checked=true なら音声ON、falseならOFF
    const enabled = !!this.awayAudioTarget.checked
    this._audioTrack.enabled = enabled
  }

  _syncUI() {
    // 1) 配信開始/終了トグル
    if (this.hasStartBtnTarget && this.hasEndBtnTarget) {
      if (this._broadcasting) {
        this.startBtnTarget.classList.add("d-none")
        this.endBtnTarget.classList.remove("d-none")
      } else {
        this.startBtnTarget.classList.remove("d-none")
        this.endBtnTarget.classList.add("d-none")
      }
    }

    // 2) 席外し/復帰ボタンの活性
    const canToggleAway = this._broadcasting

    if (this.hasAwayBtnTarget) {
      this.awayBtnTarget.disabled = !canToggleAway || this._boothStatus === "away"
    }
    if (this.hasBackBtnTarget) {
      this.backBtnTarget.disabled = !canToggleAway || this._boothStatus !== "away"
    }
    if (this.hasAwayBtnTarget && this.hasBackBtnTarget) {
      if (this._boothStatus === "away") {
        this.awayBtnTarget.classList.add("d-none")
        this.backBtnTarget.classList.remove("d-none")
      } else {
        this.awayBtnTarget.classList.remove("d-none")
        this.backBtnTarget.classList.add("d-none")
      }
    }

    // 3) 席外し中 音声トグル
    this._syncAwayAudioUI()

    // サマリーへ戻る
    if (this.hasSummaryBtnTarget) {
      const visible = (this._boothStatus === "standby") && !this._broadcasting
      this.summaryBtnTarget.classList.toggle("d-none", !visible)
      this.summaryBtnTarget.disabled = !visible
    }

    // ★startボタンのラベル切替（復帰候補なら「配信に戻る」）
    if (this.hasStartBtnTarget) {
      const normal = this.startBtnTarget.dataset.labelNormal || "配信開始"
      const resume = this.startBtnTarget.dataset.labelResume || "配信に戻る"
      this.startBtnTarget.textContent = this._resumable ? resume : normal
    }
  }

  onBoothStatusPatched(event) {
    if (!event?.detail?.success) return

    // どっちが押されたかは form の action から判定できる
    const form = event.target
    const action = form?.getAttribute("action") || ""
    if (action.includes("to=away")) this._boothStatus = "away"
    if (action.includes("to=live")) this._boothStatus = "live"

    if (this._boothStatus === "away") this.setAway()
    else this.setLive()

    this._syncUI()
  }

  // -------------------------
  // internal: mode apply
  // -------------------------
  _applyAwayMode() {
    // away はデフォルトミュート
    if (this._audioTrack) this._audioTrack.enabled = false

    // ★ 送出（canvas）を見せる
    if (this.hasPreviewTarget) this.previewTarget.classList.add("d-none")
    if (this.hasCanvasTarget) this.canvasTarget.classList.remove("d-none")

    this._syncAwayAudioUI()
  }

  _applyNormalMode() {
    // normal は音声ON
    if (this._audioTrack) this._audioTrack.enabled = true

    // ★ カメラプレビューを見せる
    if (this.hasCanvasTarget) this.canvasTarget.classList.add("d-none")
    if (this.hasPreviewTarget) this.previewTarget.classList.remove("d-none")

    this._syncAwayAudioUI()
  }

  _syncAwayAudioUI() {
    if (!this.hasAwayAudioTarget) return
    const inAway = this._mode === "away"
    this.awayAudioTarget.disabled = !inAway

    // awayのときはデフォルトOFFに見せる
    if (inAway) this.awayAudioTarget.checked = false
    else this.awayAudioTarget.checked = false
  }

  // -------------------------
  // internal: canvas draw loop
  // -------------------------
  _startCanvasRenderLoop() {
    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")

    const draw = () => {
      try {
        ctx.clearRect(0, 0, canvas.width, canvas.height)

        if (this._mode === "away") {
          // 席外し中画面（最小）
          ctx.fillStyle = "#111"
          ctx.fillRect(0, 0, canvas.width, canvas.height)
          ctx.fillStyle = "#fff"
          ctx.font = "48px sans-serif"
          ctx.fillText("席外し中", 60, 120)
        } else {
          // normal：preview video を canvas へ描画（viewerには非ミラーで届く）
          const v = this.previewTarget
          if (v && v.readyState >= 2) {
            ctx.drawImage(v, 0, 0, canvas.width, canvas.height)
          } else {
            ctx.fillStyle = "#000"
            ctx.fillRect(0, 0, canvas.width, canvas.height)
          }
        }
      } catch (_) {
        // 描画失敗は握りつぶし（次フレームへ）
      }

      this._raf = requestAnimationFrame(draw)
    }

    if (this._raf) cancelAnimationFrame(this._raf)
    this._raf = requestAnimationFrame(draw)
  }

  // -------------------------
  // internal: server calls
  // -------------------------
  async _fetchParticipantToken(role) {
    const resp = await fetch(this.tokenUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ role }),
    })

    let body = null
    try { body = await resp.json() } catch (_) {}

    if (!resp.ok) {
      throw new Error(`token_api_failed(${resp.status}) ${body?.error || ""}`.trim())
    }
    return body.participant_token
  }

  async _patchBoothStatus(to) {
    console.log("[ivs-publisher] statusUrlValue=", this.statusUrlValue, "to=", to)
    if (!this.statusUrlValue) return

    const url = new URL(this.statusUrlValue, window.location.origin)
    url.searchParams.set("to", to)

    const resp = await fetch(url.toString(), {
      method: "PATCH",
      redirect: "manual",
      credentials: "same-origin",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
    })

    if (resp.status >= 300 && resp.status < 400) {
      return
    }
    if (!resp.ok) throw new Error(`booth_status_failed(${resp.status})`)

    // Turbo Stream を手動適用
    const html = await resp.text()
    if (html && window.Turbo?.renderStreamMessage) {
      window.Turbo.renderStreamMessage(html)
    }
  }

  async _postFinish() {
    const resp = await fetch(this.finishUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Accept": "text/html, application/xhtml+xml",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      }
    })
    if (!resp.ok) throw new Error(`finish_failed(${resp.status})`)
  }

  // -------------------------
  // cleanup
  // -------------------------
  _cleanupStage() {
    this._stage = null
  }

  _cleanupMediaAndCanvas() {
    if (this._raf) cancelAnimationFrame(this._raf)
    this._raf = null

    if (this.previewTarget?.srcObject) this.previewTarget.srcObject = null

    if (this._media) {
      this._media.getTracks().forEach((t) => t.stop())
      this._media = null
    }

    this._audioTrack = null
    this._canvasStream = null
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

    if (msg.includes("token_api_failed(403)")) {
      return "このブースの配信者ではありません（担当キャストのみ配信できます）。"
    }
    if (msg.includes("token_api_failed(409) stage_not_bound")) {
      return "ステージが未準備です（stage_not_bound）。"
    }
    if (msg.includes("token_api_failed(409) not_joinable")) {
      return "まだ配信開始できない状態です（not_joinable：スタンバイ/配信状態を確認）。"
    }
    if (msg.includes("not loaded")) {
      return "IVS SDK の読み込みに失敗しました（script tag を確認してください）。"
    }

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

  _resumeKey() {
    // booth単位で復帰候補を持つ
    return `ivs:resume:${window.location.pathname}`
  }
}
