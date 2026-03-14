import { Controller } from "@hotwired/stimulus"
import { clearError, humanizeError, setError } from "controllers/ivs_publisher/errors"
import { fetchParticipantToken, patchBoothStatus, postFinish, reloadMetaDisplay } from "controllers/ivs_publisher/api_client"
import { syncCanvasResolutionToMeasured, startCanvasRenderLoop, stopCanvasRenderLoop } from "controllers/ivs_publisher/away_canvas"
import { destroyBanubaPlayer, ensureBanubaPublishTrack, ensureBanubaStarted, waitForBanubaRenderedNode } from "controllers/ivs_publisher/banuba_session"
import { cleanupBanubaPublishTrack, cleanupCameraMedia, cleanupMediaAndCanvas, cleanupStage, ensureAudioTrack, ensureCameraVideoTrack, ensureCanvasPublishTrack } from "controllers/ivs_publisher/media_state"
import { applyCurrentMode, syncMicUI, syncUI } from "controllers/ivs_publisher/ui_state"

export default class extends Controller {
  static targets = [
    "banubaSurface",
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
    initialBoothStatus: String,

    banubaClientToken: String,
    banubaSdkBaseUrl: String,
    banubaFaceTrackerUrl: String,
    banubaEyesUrl: String,
    banubaLipsUrl: String,
    banubaSkinUrl: String,
    banubaEffectUrl: String,
    banubaEffectName: String,
  }

  connect() {
    this._stage = null
    this._strategy = null

    this._cameraMedia = null
    this._cameraVideoTrack = null

    this._audioMedia = null
    this._audioTrack = null

    this._canvasStream = null
    this._canvasVideoTrack = null

    this._banubaPlayer = null
    this._banubaStarted = false
    this._banubaRenderedNode = null
    this._banubaStream = null
    this._banubaVideoTrack = null

    this._banubaStageStream = null
    this._canvasStageStream = null
    this._audioStageStream = null
    this._currentVideoStageStream = null

    this._publishedVideoTrack = null
    this._publishedVideoSource = null

    this._state = "idle"
    this._mode = this.initialModeValue === "away" ? "away" : "normal"
    this._raf = null

    this._previewOnly = false
    this._micEnabled = true
    this._lastManualMicEnabled = true
    this._switchingVideoSource = false

    this._measuredVideo = {
      width: 1280,
      height: 720,
      aspectRatio: 1280 / 720,
    }

    this._beforeCache = async () => {
      if (this._broadcasting) {
        sessionStorage.setItem(this._resumeKey(), "1")
      }
      await this.endBroadcast({ skipFinish: true })
    }
    document.addEventListener("turbo:before-cache", this._beforeCache)

    if (this.mirrorValue && this.hasBanubaSurfaceTarget) {
      this.banubaSurfaceTarget.classList.add("is-mirrored")
    }

    this._setState("idle")
    this._boothStatus = this.initialBoothStatusValue || "offline"
    this._broadcasting = false

    this._resumable =
      (this._boothStatus === "live" || this._boothStatus === "away")
    this._syncUI()

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
    void this._cleanupMediaAndCanvas()
  }

  async startBroadcast() {
    if (this._stage) return

    if (!this.hasTokenUrlValue) {
      this._setError("スタンバイを開始してください（配信セッションがありません）。")
      return
    }

    if (!this.banubaClientTokenValue) {
      this._setError("Banuba の client token が未設定です。")
      return
    }

    this._clearError()
    this._setState("starting")

    try {
      await this._ensureBanubaStarted()
      await this._ensureBanubaPublishTrack()
      await this._ensureAudioTrack()

      const token = await this._fetchParticipantToken("publisher")

      const { Stage, LocalStageStream, SubscribeType, StageEvents } = window.IVSBroadcastClient || {}
      if (!Stage || !LocalStageStream) {
        throw new Error("IVS SDK not loaded (IVSBroadcastClient is missing)")
      }

      this._banubaStageStream = this._banubaVideoTrack ? new LocalStageStream(this._banubaVideoTrack) : null
      this._audioStageStream = this._audioTrack ? new LocalStageStream(this._audioTrack) : null

      this._applyManualMicState()

      if (this._mode === "away") {
        this._ensureCanvasPublishTrack()
        this._currentVideoStageStream = this._canvasStageStream
        this._publishedVideoTrack = this._canvasVideoTrack
        this._publishedVideoSource = this._canvasVideoTrack ? "canvas" : null
      } else {
        this._currentVideoStageStream = this._banubaStageStream
        this._publishedVideoTrack = this._banubaVideoTrack
        this._publishedVideoSource = this._banubaVideoTrack ? "banuba" : null
      }

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
      this._previewOnly = false
      this._syncUI()

      await this._patchBoothStatus("live")
      this._boothStatus = "live"
      this._mode = "normal"
      this._syncUI()

      await this._reloadMetaDisplay()
      this._applyCurrentMode()
    } catch (e) {
      this._setState("error")
      this._setError(this._humanizeError(e))
      this._cleanupStage()
      await this._cleanupMediaAndCanvas()
    }

    this._syncUI()
  }

  async endBroadcast(opts = {}) {
    const { skipFinish = false } = opts
    this._setState("stopping")

    try {
      if (this._stage) {
        try {
          this._stage.leave()
        } catch (_) {}
      }
    } finally {
      this._cleanupStage()
      await this._cleanupMediaAndCanvas()
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
      targetVideoSource = "banuba"
    } else {
      return
    }

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
      await this._refreshStageStrategy()
      return
    }

    if (source === "banuba") {
      await this._ensureBanubaPublishTrack()
      if (!this._banubaStageStream || !this._banubaVideoTrack) {
        throw new Error("banuba_publish_track_unavailable")
      }

      this._currentVideoStageStream = this._banubaStageStream
      this._publishedVideoTrack = this._banubaVideoTrack
      this._publishedVideoSource = "banuba"
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

  async _startPreviewOnlyIfNeeded() {
    if (!this.hasTokenUrlValue) return
    if (this._stage || this._broadcasting) return
    if (this._banubaStarted) return

    this._clearError()

    try {
      await this._ensureBanubaStarted()
      await this._ensureBanubaPublishTrack()

      this._previewOnly = true
      this._applyCurrentMode()
    } catch (e) {
      this._setError(this._humanizeError(e))
      await this._destroyBanubaPlayer()
      this._cleanupBanubaPublishTrack()
      this._cleanupCameraMedia()
      this._previewOnly = false
    } finally {
      this._syncUI()
    }
  }

  _nextFrame() {
    return new Promise((resolve) => requestAnimationFrame(() => resolve()))
  }

  _captureMeasuredBanubaNode(node) {
    if (!node) return

    const rect = node.getBoundingClientRect?.()
    const width =
      Number(node.videoWidth) ||
      Number(node.width) ||
      Math.round(rect?.width || 0) ||
      null

    const height =
      Number(node.videoHeight) ||
      Number(node.height) ||
      Math.round(rect?.height || 0) ||
      null

    if (width && height) {
      this._measuredVideo = {
        width,
        height,
        aspectRatio: width / height,
      }
      this._syncCanvasResolutionToMeasured()
    }
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

  _setState(s) {
    this._state = s
    if (this.hasStateTarget) this.stateTarget.textContent = s
  }

  _clearError() {
    clearError(this)
  }

  _setError(msg) {
    setError(this, msg)
  }

  _humanizeError(err) {
    return humanizeError(err)
  }

  _fetchParticipantToken(role) {
    return fetchParticipantToken(this, role)
  }

  _patchBoothStatus(to) {
    return patchBoothStatus(this, to)
  }

  _reloadMetaDisplay() {
    return reloadMetaDisplay(this)
  }

  _postFinish() {
    return postFinish(this)
  }

  _syncCanvasResolutionToMeasured() {
    syncCanvasResolutionToMeasured(this)
  }

  _startCanvasRenderLoop() {
    startCanvasRenderLoop(this)
  }

  _stopCanvasRenderLoop() {
    stopCanvasRenderLoop(this)
  }

  _ensureBanubaStarted() {
    return ensureBanubaStarted(this)
  }

  _ensureBanubaPublishTrack() {
    return ensureBanubaPublishTrack(this)
  }

  _destroyBanubaPlayer() {
    return destroyBanubaPlayer(this)
  }

  _waitForBanubaRenderedNode() {
    return waitForBanubaRenderedNode(this)
  }

  _ensureCameraVideoTrack() {
    return ensureCameraVideoTrack(this)
  }

  _ensureAudioTrack() {
    return ensureAudioTrack(this)
  }

  _ensureCanvasPublishTrack() {
    return ensureCanvasPublishTrack(this)
  }

  _cleanupStage() {
    cleanupStage(this)
  }

  _cleanupBanubaPublishTrack() {
    cleanupBanubaPublishTrack(this)
  }

  _cleanupCameraMedia() {
    cleanupCameraMedia(this)
  }

  _cleanupMediaAndCanvas() {
    return cleanupMediaAndCanvas(this)
  }

  _syncMicUI() {
    syncMicUI(this)
  }

  _syncUI() {
    syncUI(this)
  }

  _applyCurrentMode() {
    applyCurrentMode(this)
  }

  _resumeKey() {
    return `ivs:resume:${window.location.pathname}`
  }
}
