import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "preview",
    "canvas",
    "error",
    "state",
    "startBtn",
    "endBtn",
    "summaryBtn",
    "summaryPanel",
    "metaPanel",
    "drinkPanel",
    "opsPanel",
    "cameraOnBtn",
    "cameraOffBtn",
    "micBtn",
    "micIcon",
  ]

  static values = {
    tokenUrl: String,
    finishUrl: String,
    statusUrl: String,
    metaDisplayUrl: String,
    mirror: { type: Boolean, default: true },
    initialMode: { type: String, default: "normal" },
    initialBoothStatus: String, // "offline" | "live" | "away" | "standby" etc
  }

  connect() {
    this._stage = null
    this._strategy = null

    this._media = null
    this._audioTrack = null

    this._canvasStream = null
    this._canvasVideoTrack = null

    this._cameraVideoTrack = null
    this._cameraStageStream = null
    this._canvasStageStream = null
    this._audioStageStream = null
    this._currentVideoStageStream = null

    this._publishedVideoTrack = null
    this._publishedVideoSource = null // "camera" | "canvas" | null

    this._state = "idle"
    this._mode = this.initialModeValue === "away" ? "away" : "normal"
    this._raf = null

    // standby preview-only のフラグ
    this._previewOnly = false

    // 現在の実mic状態
    this._micEnabled = true

    // 最後にユーザーが手動で選んだ mic 状態
    // 一度も操作していない場合は初期値 ON
    this._lastManualMicEnabled = true

    // video publish切替中フラグ
    this._switchingVideoSource = false

    // before-cache でフラグを立ててから片付ける
    this._measuredVideo = {
      width: 1280,
      height: 720,
      aspectRatio: 1280 / 720,
    }

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
    this._setState("idle")
    this._boothStatus = this.initialBoothStatusValue || "offline"
    this._broadcasting = false

    // boothが live/away なら常に復帰候補
    this._resumable =
      (this._boothStatus === "live" || this._boothStatus === "away")
    this._syncUI()

    // standby では preview-only を自動起動
    if (this._boothStatus === "standby") {
      this._startPreviewOnlyIfNeeded()
    }
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this._beforeCache)

    if (this._broadcasting) {
      sessionStorage.setItem(this._resumeKey(), "1")
    }

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
      this._logOrientationInputs("broadcast:start")

      // standby preview-only が動いていたら必ず止めてから取り直す
      if (this._previewOnly && this._media) {
        try {
          this._media.getTracks().forEach((t) => t.stop())
        } catch (_) {}
        this._media = null
        this._previewOnly = false
        if (this.previewTarget?.srcObject) this.previewTarget.srcObject = null
      }

      // 1) getUserMedia（preview用 + audio用）
      const videoConstraints = this._buildCameraVideoConstraints()
      console.log("[ivs-publisher] camera constraints", {
        label: "broadcast",
        portraitByViewport: this._isPortraitViewport(),
        forcedLandscape: true,
        requestedConstraints: videoConstraints,
      })

      this._media = await navigator.mediaDevices.getUserMedia({
        video: videoConstraints,
        audio: true,
      })

      this._cameraVideoTrack = this._media.getVideoTracks()[0] || null
      this._audioTrack = this._media.getAudioTracks()[0] || null

      this._captureMeasuredVideoTrack(this._cameraVideoTrack)
      this._logMeasuredVideoTrack("broadcast", this._cameraVideoTrack, videoConstraints)
      this._syncCanvasResolutionToMeasured()

      // preview（ミラーは video 要素だけ）
      this.previewTarget.srcObject = this._media
      try { await this.previewTarget.play() } catch (_) {}
      this._logPreviewMetrics("broadcast")

      // 2) publisher token
      const token = await this._fetchParticipantToken("publisher")

      // 3) publish track を構築
      const { Stage, LocalStageStream, SubscribeType, StageEvents } = window.IVSBroadcastClient || {}
      if (!Stage || !LocalStageStream) {
        throw new Error("IVS SDK not loaded (IVSBroadcastClient is missing)")
      }

      this._cameraStageStream = this._cameraVideoTrack ? new LocalStageStream(this._cameraVideoTrack) : null
      this._audioStageStream = this._audioTrack ? new LocalStageStream(this._audioTrack) : null

      // 配信開始時は最後の手動状態をそのまま適用
      this._applyManualMicState()

      if (this._mode === "away") {
        this._ensureCanvasPublishTrack()
        this._currentVideoStageStream = this._canvasStageStream
        this._publishedVideoTrack = this._canvasVideoTrack
        this._publishedVideoSource = this._canvasVideoTrack ? "canvas" : null
      } else {
        this._currentVideoStageStream = this._cameraStageStream
        this._publishedVideoTrack = this._cameraVideoTrack
        this._publishedVideoSource = this._cameraVideoTrack ? "camera" : null
      }

      this._logPublishSourceTrack("broadcast:before-join")

      this._strategy = {
        stageStreamsToPublish: () => {
          const streams = []
          if (this._currentVideoStageStream) streams.push(this._currentVideoStageStream)
          if (this._audioStageStream) streams.push(this._audioStageStream)
          return streams
        },
        shouldPublishParticipant: () => true,
        shouldSubscribeToParticipant: () => SubscribeType.NONE,
      }

      this._stage = new Stage(token, this._strategy)

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
      this._mode = "normal"
      this._syncUI()

      // 6) live開始時に meta 表示を最新化
      await this._reloadMetaDisplay()

      // 7) 現在モードを適用（audioは独立）
      this._applyCurrentMode()
    } catch (e) {
      this._setState("error")
      this._setError(this._humanizeError(e))
      this._cleanupStage()
      this._cleanupMediaAndCanvas()
    }

    this._syncUI()
  }

  /**
   * 配信終了
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
      this._previewOnly = false
      this._switchingVideoSource = false
      this._syncUI()

      if (!skipFinish && this.finishUrlValue) {
        const redirectUrl = await this._postFinish()

        if (redirectUrl) {
          if (window.Turbo?.visit) {
            window.Turbo.visit(redirectUrl)
          } else {
            window.location.assign(redirectUrl)
          }
        } else {
          window.location.reload()
        }
      }
    }
  }

  toggleMic() {
    this._lastManualMicEnabled = !this._lastManualMicEnabled
    this._applyManualMicState()
    this._syncMicUI()
  }

  async onBoothStatusPatched(event) {
    if (!event?.detail?.success) return
    if (this._switchingVideoSource) return

    const form = event.target
    const action = form?.getAttribute("action") || ""

    let targetBoothStatus = null
    let targetMode = null
    let targetVideoSource = null

    if (action.includes("to=away")) {
      targetBoothStatus = "away"
      targetMode = "away"
      targetVideoSource = "canvas"
    } else if (action.includes("to=live")) {
      targetBoothStatus = "live"
      targetMode = "normal"
      targetVideoSource = "camera"
    } else {
      return
    }

    // 非配信中は publish切替不要。状態だけ反映。
    if (!this._broadcasting || !this._stage) {
      this._boothStatus = targetBoothStatus
      this._mode = targetMode

      if (targetMode === "away") {
        this._forceMicOffForAwayEntry()
      } else {
        this._applyManualMicState()
      }

      this._applyCurrentMode()
      this._syncUI()
      return
    }

    const prevBoothStatus = this._boothStatus
    const prevMode = this._mode
    const prevVideoSource = this._publishedVideoSource
    const prevMicEnabled = this._micEnabled

    this._switchingVideoSource = true
    this._clearError()
    this._syncUI()

    try {
      await this._switchPublishedVideoSource(targetVideoSource)

      this._boothStatus = targetBoothStatus
      this._mode = targetMode

      if (targetMode === "away") {
        this._forceMicOffForAwayEntry()
      } else {
        this._applyManualMicState()
      }

      this._applyCurrentMode()
    } catch (e) {
      console.error("[ivs-publisher] publish video switch failed", e)

      // クライアント内部状態は最後の正常値へ戻す
      this._boothStatus = prevBoothStatus
      this._mode = prevMode
      this._micEnabled = prevMicEnabled

      try {
        if (prevVideoSource && prevVideoSource !== this._publishedVideoSource) {
          await this._switchPublishedVideoSource(prevVideoSource)
        }
      } catch (restoreError) {
        console.error("[ivs-publisher] publish video restore failed", restoreError)
      }

      this._applyMicTrackEnabled()
      this._applyCurrentMode()
      this._setError("映像切替に失敗しました。もう一度お試しください。")
    } finally {
      this._switchingVideoSource = false
      this._syncUI()
    }
  }

  // -------------------------
  // internal: mode apply
  // -------------------------
  _applyCurrentMode() {
    if (this._mode === "away") {
      this._applyAwayMode()
    } else {
      this._applyNormalMode()
    }
  }

  _applyAwayMode() {
    if (this.hasPreviewTarget) this.previewTarget.classList.add("d-none")
    if (this.hasCanvasTarget) this.canvasTarget.classList.remove("d-none")

    this._syncCanvasResolutionToMeasured()
    this._startCanvasRenderLoop()

    if (this._broadcasting && this._publishedVideoSource !== "canvas" && !this._switchingVideoSource) {
      this._setError("映像状態の同期が必要です。もう一度お試しください。")
    }
  }

  _applyNormalMode() {
    if (this.hasCanvasTarget) this.canvasTarget.classList.add("d-none")
    if (this.hasPreviewTarget) this.previewTarget.classList.remove("d-none")

    if (!this._broadcasting && this._publishedVideoSource !== "canvas") {
      this._stopCanvasRenderLoop()
    }

    if (this._broadcasting && this._publishedVideoSource !== "camera" && !this._switchingVideoSource) {
      this._setError("映像状態の同期が必要です。もう一度お試しください。")
    }
  }

  async _switchPublishedVideoSource(source) {
    if (!this._broadcasting || !this._stage) return

    if (source === this._publishedVideoSource) return

    if (source === "canvas") {
      this._ensureCanvasPublishTrack()
      if (!this._canvasStageStream || !this._canvasVideoTrack) {
        throw new Error("canvas_publish_track_unavailable")
      }

      this._currentVideoStageStream = this._canvasStageStream
      this._publishedVideoTrack = this._canvasVideoTrack
      this._publishedVideoSource = "canvas"
      this._logPublishSourceTrack("switch:canvas")
      await this._refreshStageStrategy()
      return
    }

    if (source === "camera") {
      if (!this._cameraStageStream || !this._cameraVideoTrack) {
        throw new Error("camera_publish_track_unavailable")
      }

      this._currentVideoStageStream = this._cameraStageStream
      this._publishedVideoTrack = this._cameraVideoTrack
      this._publishedVideoSource = "camera"
      this._logPublishSourceTrack("switch:camera")
      await this._refreshStageStrategy()
      this._stopCanvasRenderLoop()
      return
    }

    throw new Error(`unknown_video_source(${source})`)
  }

  async _refreshStageStrategy() {
    if (!this._stage) return

    if (typeof this._stage.refreshStrategy === "function") {
      try {
        await this._stage.refreshStrategy()
      } catch (e) {
        console.error("[ivs-publisher] refreshStrategy failed", e)
        throw e
      }
      return
    }

    console.warn("[ivs-publisher] stage.refreshStrategy is not available")
    throw new Error("stage_refresh_strategy_not_supported")
  }

  _ensureCanvasPublishTrack() {
    this._syncCanvasResolutionToMeasured()
    this._startCanvasRenderLoop()

    if (this._canvasVideoTrack && this._canvasStageStream) return

    const stream = this.canvasTarget.captureStream(15)
    const track = stream.getVideoTracks()[0] || null

    this._canvasStream = stream
    this._canvasVideoTrack = track

    const { LocalStageStream } = window.IVSBroadcastClient || {}
    this._canvasStageStream = (track && LocalStageStream) ? new LocalStageStream(track) : null

    console.log("[ivs-publisher] canvas publish track prepared", {
      canvasWidth: this.canvasTarget?.width ?? null,
      canvasHeight: this.canvasTarget?.height ?? null,
      canvasTrackSettings: this._safeTrackSettings(track),
      measuredVideo: this._measuredVideo,
    })
  }

  _captureMeasuredVideoTrack(track) {
    if (!track || typeof track.getSettings !== "function") return

    const settings = track.getSettings() || {}
    const width = Number(settings.width) || null
    const height = Number(settings.height) || null
    const aspectRatio = Number(settings.aspectRatio) || null

    if (width && height) {
      this._measuredVideo = {
        width,
        height,
        aspectRatio: aspectRatio || (width / height),
      }
      return
    }

    if (aspectRatio) {
      const fallbackWidth = this._measuredVideo.width || 1280
      const fallbackHeight = Math.round(fallbackWidth / aspectRatio)
      this._measuredVideo = {
        width: fallbackWidth,
        height: fallbackHeight,
        aspectRatio,
      }
    }
  }

  _syncCanvasResolutionToMeasured() {
    if (!this.hasCanvasTarget) return

    const width = Math.max(1, Math.round(this._measuredVideo?.width || 1280))
    const height = Math.max(1, Math.round(this._measuredVideo?.height || 720))

    if (this.canvasTarget.width !== width) this.canvasTarget.width = width
    if (this.canvasTarget.height !== height) this.canvasTarget.height = height

    console.log("[ivs-publisher] canvas resolution synced", {
      canvasWidth: this.canvasTarget.width,
      canvasHeight: this.canvasTarget.height,
      measuredVideo: this._measuredVideo,
    })
  }

  _applyMicTrackEnabled() {
    if (this._audioTrack) {
      this._audioTrack.enabled = !!this._micEnabled
    }
  }

  _applyManualMicState() {
    this._micEnabled = !!this._lastManualMicEnabled
    this._applyMicTrackEnabled()
  }

  _forceMicOffForAwayEntry() {
    this._micEnabled = false
    this._applyMicTrackEnabled()
  }

  _syncMicUI() {
    if (!this.hasMicBtnTarget || !this.hasMicIconTarget) return

    this.micBtnTarget.disabled = !this._broadcasting
    this.micBtnTarget.classList.toggle("is-off", !this._micEnabled)
    this.micBtnTarget.setAttribute(
      "aria-label",
      this._micEnabled ? "マイクをオフにする" : "マイクをオンにする"
    )
    this.micBtnTarget.setAttribute(
      "title",
      this._micEnabled ? "マイクON" : "マイクOFF"
    )

    this.micIconTarget.className = this._micEnabled
      ? "bi bi-mic-fill"
      : "bi bi-mic-mute-fill"
  }

  _syncUI() {
    if (this.hasStartBtnTarget && this.hasEndBtnTarget) {
      if (this._broadcasting) {
        this.startBtnTarget.classList.add("d-none")
        this.endBtnTarget.classList.remove("d-none")
      } else {
        this.startBtnTarget.classList.remove("d-none")
        this.endBtnTarget.classList.add("d-none")
      }
    }

    const canToggleCamera = this._broadcasting && !this._switchingVideoSource

    if (this.hasCameraOffBtnTarget) {
      this.cameraOffBtnTarget.disabled = !canToggleCamera || this._boothStatus === "away"
      this.cameraOffBtnTarget.classList.toggle("d-none", this._boothStatus === "away")
    }

    if (this.hasCameraOnBtnTarget) {
      this.cameraOnBtnTarget.disabled = !canToggleCamera || this._boothStatus !== "away"
      this.cameraOnBtnTarget.classList.toggle("d-none", this._boothStatus !== "away")
    }

    this._syncMicUI()

    if (this.hasSummaryPanelTarget) {
      const visible = (this._boothStatus === "standby") && !this._broadcasting
      this.summaryPanelTarget.classList.toggle("d-none", !visible)
    }

    if (this.hasSummaryBtnTarget) {
      const visible = (this._boothStatus === "standby") && !this._broadcasting
      this.summaryBtnTarget.classList.toggle("d-none", !visible)
      this.summaryBtnTarget.disabled = !visible
    }

    if (this.hasStartBtnTarget) {
      const normal = this.startBtnTarget.dataset.labelNormal || "配信開始"
      const resume = this.startBtnTarget.dataset.labelResume || "配信に戻る"
      this.startBtnTarget.textContent = this._resumable ? resume : normal
    }

    if (this.hasMetaPanelTarget) {
      const visible =
        this._boothStatus === "standby" ||
        this._boothStatus === "live" ||
        this._boothStatus === "away" ||
        this._broadcasting

      this.metaPanelTarget.classList.toggle("d-none", !visible)
    }

    if (this.hasDrinkPanelTarget) {
      const visible =
        this._broadcasting ||
        this._boothStatus === "live" ||
        this._boothStatus === "away"

      this.drinkPanelTarget.classList.toggle("d-none", !visible)
    }

    if (this.hasOpsPanelTarget) {
      const visible = this._broadcasting
      this.opsPanelTarget.classList.toggle("d-none", !visible)
    }
  }

  // -------------------------
  // internal: standby preview-only
  // -------------------------
  async _startPreviewOnlyIfNeeded() {
    if (!this.hasTokenUrlValue) return
    if (this._media || this._stage || this._broadcasting) return
    if (!navigator.mediaDevices?.getUserMedia) return

    this._clearError()

    try {
      this._logOrientationInputs("preview-only:start")

      const videoConstraints = this._buildCameraVideoConstraints()
      console.log("[ivs-publisher] camera constraints", {
        label: "preview-only",
        portraitByViewport: this._isPortraitViewport(),
        forcedLandscape: true,
        requestedConstraints: videoConstraints,
      })

      const stream = await navigator.mediaDevices.getUserMedia({
        video: videoConstraints,
        audio: false,
      })

      const previewTrack = stream.getVideoTracks()[0] || null
      this._captureMeasuredVideoTrack(previewTrack)
      this._logMeasuredVideoTrack("preview-only", previewTrack, videoConstraints)
      this._syncCanvasResolutionToMeasured()

      this._media = stream
      this._previewOnly = true

      this.previewTarget.srcObject = stream
      try { await this.previewTarget.play() } catch (_) {}
      this._logPreviewMetrics("preview-only")
    } catch (e) {
      this._setError(this._humanizeError(e))
      try {
        if (this.previewTarget?.srcObject) this.previewTarget.srcObject = null
      } catch (_) {}

      if (this._media) {
        try { this._media.getTracks().forEach((t) => t.stop()) } catch (_) {}
        this._media = null
      }

      this._previewOnly = false
    } finally {
      this._syncUI()
    }
  }

  _buildCameraVideoConstraints() {
    const maxWidth = 1920
    const maxHeight = 1080

    return {
      facingMode: "user",
      width: {
        ideal: maxWidth,
        max: maxWidth,
      },
      height: {
        ideal: maxHeight,
        max: maxHeight,
      },
    }
  }

  _isPortraitViewport() {
    const vv = window.visualViewport
    const width = vv?.width || window.innerWidth || screen?.width || 0
    const height = vv?.height || window.innerHeight || screen?.height || 0
    return height >= width
  }

  _logMeasuredVideoTrack(label, track, requestedConstraints) {
    if (!track) {
      console.warn(`[ivs-publisher] ${label}: video track is not available`, {
        requestedConstraints,
      })
      return
    }

    const settings = typeof track.getSettings === "function" ? track.getSettings() : {}
    const constraints = typeof track.getConstraints === "function" ? track.getConstraints() : {}

    console.log(`[ivs-publisher] ${label}: camera video acquired`, {
      requestedConstraints,
      appliedConstraints: constraints,
      measured: {
        width: settings.width ?? null,
        height: settings.height ?? null,
        aspectRatio: settings.aspectRatio ?? null,
        facingMode: settings.facingMode ?? null,
        deviceId: settings.deviceId ?? null,
      },
    })
  }

  _logOrientationInputs(label) {
    const vv = window.visualViewport
    const orientation = window.screen?.orientation || null

    console.log("[ivs-publisher] orientation inputs", {
      label,
      portraitByViewport: this._isPortraitViewport(),
      visualViewport: {
        width: vv?.width ?? null,
        height: vv?.height ?? null,
        scale: vv?.scale ?? null,
        offsetTop: vv?.offsetTop ?? null,
        offsetLeft: vv?.offsetLeft ?? null,
      },
      windowMetrics: {
        innerWidth: window.innerWidth ?? null,
        innerHeight: window.innerHeight ?? null,
        outerWidth: window.outerWidth ?? null,
        outerHeight: window.outerHeight ?? null,
      },
      screenMetrics: {
        width: window.screen?.width ?? null,
        height: window.screen?.height ?? null,
        availWidth: window.screen?.availWidth ?? null,
        availHeight: window.screen?.availHeight ?? null,
      },
      screenOrientation: {
        type: orientation?.type ?? null,
        angle: orientation?.angle ?? null,
      },
    })
  }

  _logPreviewMetrics(label) {
    if (!this.hasPreviewTarget) return

    const rect = this.previewTarget.getBoundingClientRect()

    console.log("[ivs-publisher] preview video metrics", {
      label,
      video: {
        videoWidth: this.previewTarget.videoWidth ?? null,
        videoHeight: this.previewTarget.videoHeight ?? null,
        readyState: this.previewTarget.readyState ?? null,
      },
      layout: {
        clientWidth: this.previewTarget.clientWidth ?? null,
        clientHeight: this.previewTarget.clientHeight ?? null,
        rectWidth: rect?.width ?? null,
        rectHeight: rect?.height ?? null,
        rectTop: rect?.top ?? null,
        rectLeft: rect?.left ?? null,
      },
      measuredVideo: this._measuredVideo,
      publishedVideoSource: this._publishedVideoSource,
    })
  }

  _logPublishSourceTrack(label) {
    console.log("[ivs-publisher] publish source track", {
      label,
      publishedVideoSource: this._publishedVideoSource,
      currentVideoTrack: this._safeTrackSettings(this._publishedVideoTrack),
      cameraVideoTrack: this._safeTrackSettings(this._cameraVideoTrack),
      canvasVideoTrack: this._safeTrackSettings(this._canvasVideoTrack),
      measuredVideo: this._measuredVideo,
      canvasSize: this.hasCanvasTarget
        ? {
            width: this.canvasTarget.width ?? null,
            height: this.canvasTarget.height ?? null,
          }
        : null,
    })
  }

  _safeTrackSettings(track) {
    if (!track || typeof track.getSettings !== "function") return null

    const settings = track.getSettings() || {}
    return {
      width: settings.width ?? null,
      height: settings.height ?? null,
      aspectRatio: settings.aspectRatio ?? null,
      facingMode: settings.facingMode ?? null,
      deviceId: settings.deviceId ?? null,
      frameRate: settings.frameRate ?? null,
    }
  }

  // -------------------------
  // internal: canvas draw loop
  // -------------------------
  _startCanvasRenderLoop() {
    if (!this.hasCanvasTarget) return
    if (this._raf) return

    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")

    const draw = () => {
      try {
        const width = canvas.width
        const height = canvas.height

        ctx.clearRect(0, 0, width, height)

        if (this._mode === "away") {
          ctx.fillStyle = "#111"
          ctx.fillRect(0, 0, width, height)

          const minSide = Math.min(width, height)
          const fontSize = Math.max(28, Math.round(minSide * 0.1))
          const subFontSize = Math.max(16, Math.round(minSide * 0.045))

          ctx.fillStyle = "#fff"
          ctx.textAlign = "center"
          ctx.textBaseline = "middle"
          ctx.font = `700 ${fontSize}px sans-serif`
          ctx.fillText("席外し中", width / 2, height / 2 - fontSize * 0.15)

          ctx.fillStyle = "rgba(255, 255, 255, 0.75)"
          ctx.font = `400 ${subFontSize}px sans-serif`
          ctx.fillText("しばらくお待ちください", width / 2, height / 2 + fontSize * 0.8)
        } else {
          const v = this.previewTarget
          if (v && v.readyState >= 2) {
            ctx.drawImage(v, 0, 0, width, height)
          } else {
            ctx.fillStyle = "#000"
            ctx.fillRect(0, 0, width, height)
          }
        }
      } catch (_) {
      }

      this._raf = requestAnimationFrame(draw)
    }

    this._raf = requestAnimationFrame(draw)
  }

  _stopCanvasRenderLoop() {
    if (this._raf) cancelAnimationFrame(this._raf)
    this._raf = null

    if (!this.hasCanvasTarget) return

    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")
    if (ctx) {
      try {
        ctx.clearRect(0, 0, canvas.width, canvas.height)
      } catch (_) {}
    }
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

    const html = await resp.text()
    if (html && window.Turbo?.renderStreamMessage) {
      window.Turbo.renderStreamMessage(html)
    }
  }

  async _reloadMetaDisplay() {
    if (!this.hasMetaDisplayUrlValue) return

    const frame = document.getElementById("stream_meta_display")
    if (!frame) return

    const currentSrc = frame.getAttribute("src")
    if (currentSrc === this.metaDisplayUrlValue) {
      if (typeof frame.reload === "function") {
        await frame.reload()
      } else {
        frame.removeAttribute("src")
        frame.setAttribute("src", this.metaDisplayUrlValue)
      }
      return
    }

    frame.setAttribute("src", this.metaDisplayUrlValue)
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

    return resp.url
  }

  // -------------------------
  // cleanup
  // -------------------------
  _cleanupStage() {
    this._stage = null
    this._strategy = null
    this._cameraStageStream = null
    this._canvasStageStream = null
    this._audioStageStream = null
    this._currentVideoStageStream = null
  }

  _cleanupMediaAndCanvas() {
    this._stopCanvasRenderLoop()

    if (this.previewTarget?.srcObject) this.previewTarget.srcObject = null

    if (this._media) {
      this._media.getTracks().forEach((t) => t.stop())
      this._media = null
    }

    if (this._canvasStream) {
      try {
        this._canvasStream.getTracks().forEach((t) => t.stop())
      } catch (_) {}
      this._canvasStream = null
    }

    this._audioTrack = null
    this._cameraVideoTrack = null
    this._canvasVideoTrack = null
    this._publishedVideoTrack = null
    this._publishedVideoSource = null
    this._previewOnly = false
    this._switchingVideoSource = false
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
    if (msg.includes("stage_refresh_strategy_not_supported")) {
      return "この環境では映像切替に未対応です。"
    }
    if (msg.includes("canvas_publish_track_unavailable")) {
      return "席外し映像の準備に失敗しました。もう一度お試しください。"
    }
    if (msg.includes("camera_publish_track_unavailable")) {
      return "カメラ映像の復帰に失敗しました。もう一度お試しください。"
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
    return `ivs:resume:${window.location.pathname}`
  }
}
