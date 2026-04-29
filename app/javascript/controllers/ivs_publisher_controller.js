import { Controller } from "@hotwired/stimulus"
import { clearError, humanizeError, setError } from "controllers/ivs_publisher/errors"
import { fetchParticipantToken, patchBoothStatus, patchBroadcastStartedAt, postFinish, reloadMetaDisplay } from "controllers/ivs_publisher/api_client"
import { syncCanvasResolutionToMeasured, startCanvasRenderLoop, stopCanvasRenderLoop } from "controllers/ivs_publisher/away_canvas"
import { waitForBanubaRenderedNode } from "controllers/ivs_publisher/banuba_session"
import { cleanupBanubaPublishTrack, cleanupCameraMedia, cleanupMediaAndCanvas, cleanupStage, ensureAudioTrack, ensureCameraVideoTrack, ensureCanvasPublishTrack } from "controllers/ivs_publisher/media_state"
import { applyCurrentMode, syncMicUI } from "controllers/ivs_publisher/ui_state"
import { BanubaProvider } from "controllers/ivs_publisher/beauty_providers/banuba_provider"
import { DeepARProvider } from "controllers/ivs_publisher/beauty_providers/deepar_provider"

export default class extends Controller {
  static targets = [
    "banubaSurface",
    "canvas",
    "error",
    "errorMessage",
    "state",
    "startBtn",
    "endBtn",
    "summaryPanel",
    "metaPanel",
    "drinkPanel",
    "opsPanel",
    "cameraOnBtn",
    "cameraOffBtn",
    "micBtn",
    "micIcon",
    "effectOpenBtn",
    "beautyAdjustBtn",
    "effectOverlay",
    "effectPanel",
    "beautyOverlay",
    "beautyPanel",
    "beautySlider",
    "beautyLabel",
    "beautyValue",
  ]

  static values = {
    tokenUrl: String,
    finishUrl: String,
    statusUrl: String,
    metaDisplayUrl: String,
    startBroadcastUrl: String,
    mirror: { type: Boolean, default: true },
    initialMode: { type: String, default: "normal" },
    initialBoothStatus: String,
    autoResumeOnEntry: { type: Boolean, default: false },
    provider: { type: String, default: "banuba" },

    deeparLicenseKey: String,
    deeparRootPath: String,
    deeparDefaultEffectUrl: String,
    banubaClientToken: String,
    banubaSdkBaseUrl: String,
    banubaFaceTrackerUrl: String,
    banubaEyesUrl: String,
    banubaLipsUrl: String,
    banubaSkinUrl: String,
    banubaBackgroundUrl: String,
    banubaHairUrl: String,
    banubaEffectUrl: String,
    banubaEffectName: String,
    banubaBeautyConfigUrl: String,
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
    this._banubaEffects = {}
    this._beautyProvider = this._createBeautyProvider()

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
    this._autoResumeAttempted = false

    this._measuredVideo = {
      width: 1280,
      height: 720,
      aspectRatio: 1280 / 720,
    }

    this._beautyConfigSource = null
    this._beautyConfigSourceLoaded = false
    this._beautyStateLoadPromise = null
    this._beautyStateInitialized = false
    this._beautyState = {
      beautyEnabled: true,
      softlightStrength: 0,
      faceNarrowing: 0,
      eyeRounding: 0,
      eyeEnlargement: 0,
      lipsSize: 0,
      lipsMouthSize: 0,
      noseLength: 0,
    }

    this._effectPanelOpen = false
    this._beautyPanelOpen = false
    this._selectedEffect = "beauty"
    this._selectedBeautyControl = "softlight"
    this._lastBeautyAdjustBtnVisible = null

    this._beforeCache = async () => {
      this.closeEffectPanel()
      this.closeBeautyPanel()
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
    this._syncEffectSelectionUI()
    this._syncEffectPanelUI()
    this._syncBeautyPanelUI()

    void this._ensureInitialBeautyStateLoaded().catch((e) => {
      console.warn("[ivs-publisher] initial beauty config load failed", e)
    })

    window.publisher = this

    if (this._boothStatus === "standby") {
      this._startPreviewOnlyIfNeeded()
      return
    }

    if (this._shouldAutoResumeOnEntry()) {
      void this._tryAutoResumeOnEntry()
    }
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this._beforeCache)

    if (window.publisher === this) {
      delete window.publisher
    }

    this.closeEffectPanel()
    this.closeBeautyPanel()

    try {
      if (this._stage) this._stage.leave()
    } catch (_) {}

    this._cleanupStage()
    void this._cleanupMediaAndCanvas()
  }

  async startBroadcast(opts = {}) {
    const { autoResume = false } = opts

    if (this._stage) return
    if (this._state === "starting" || this._state === "joining") return

    if (!this.hasTokenUrlValue) {
      this._setError("スタンバイを開始してください（配信セッションがありません）。")
      return
    }

    if (this.providerValue === "banuba" && !this.banubaClientTokenValue) {
      this._setError("Banuba の client token が未設定です。")
      return
    }

    this._clearError()
    this._setState("starting")

    try {
      await this._beautyProvider.ensureInitialBeautyStateLoaded()
      await this._beautyProvider.start()
      await this._beautyProvider.ensurePublishTrack()
      await this._ensureAudioTrack()

      const token = await this._fetchParticipantToken("publisher")

      const { Stage, LocalStageStream, SubscribeType, StageEvents } = window.IVSBroadcastClient || {}
      if (!Stage || !LocalStageStream) {
        throw new Error("IVS SDK not loaded (IVSBroadcastClient is missing)")
      }

      const shouldResumeToLive =
        this.autoResumeOnEntryValue &&
        (this._boothStatus === "live" || this._boothStatus === "away")

      if (shouldResumeToLive) {
        this._mode = "normal"
      }

      this._applyManualMicState()

      this._audioStageStream = this._audioTrack ? new LocalStageStream(this._audioTrack) : null

      const providerTrack = this._beautyProvider.videoTrack
      const providerStageStream = this._beautyProvider.stageStream

      if (!providerTrack || !providerStageStream) {
        throw new Error("provider_publish_track_unavailable")
      }

      if (this._mode === "away") {
        this._ensureCanvasPublishTrack()
        this._currentVideoStageStream = this._canvasStageStream
        this._publishedVideoTrack = this._canvasVideoTrack
        this._publishedVideoSource = this._canvasVideoTrack ? "canvas" : null
      } else {
        this._currentVideoStageStream = providerStageStream
        this._publishedVideoTrack = providerTrack
        this._publishedVideoSource = "processed"
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

      await this._patchBroadcastStartedAt()

      this._broadcasting = true
      this._previewOnly = false
      this._syncUI()

      await this._patchBoothStatus("live")
      this._boothStatus = "live"
      this._mode = "normal"
      this._syncUI()

      await this._reloadMetaDisplay()
      this._applyCurrentMode()
      this._syncEffectPanelUI()
      this._syncBeautyPanelUI()
    } catch (e) {
      this._setState("error")

      if (autoResume) {
        this._setError("復帰に失敗しました。配信に戻るボタンを押して再度復帰を試してください。")
      } else {
        this._setError(this._humanizeError(e))
      }

      this._cleanupStage()
      await this._cleanupMediaAndCanvas()
    }

    this._syncUI()
  }

  async endBroadcast(opts = {}) {
    const { skipFinish = false } = opts
    this._setState("stopping")
    this.closeEffectPanel()
    this.closeBeautyPanel()

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

  closeError() {
    this._clearError()
  }

  openEffectPanel() {
    if (!this._canUseEffectUI()) return

    this.closeBeautyPanel()
    this._effectPanelOpen = true
    this._syncEffectSelectionUI()
    this._syncEffectPanelUI()
  }

  closeEffectPanel() {
    this._effectPanelOpen = false
    this._syncEffectPanelUI()
  }

  closeEffectPanelOnBackdrop(event) {
    if (!this.hasEffectOverlayTarget) return
    if (event.target !== this.effectOverlayTarget) return
    this.closeEffectPanel()
  }

  async onEffectSelectionChanged(event) {
    const nextValue = event.target?.value
    if (!this._isSelectableEffect(nextValue)) return

    const previousEffect = this._selectedEffect

    if (nextValue === "beauty") {
      await this._ensureInitialBeautyStateLoaded()
    }

    this._selectedEffect = nextValue
    console.log("[ivs-publisher] selectedEffect:", this._selectedEffect)

    if (this._selectedEffect !== "beauty") {
      this.closeBeautyPanel()
    }

    this._syncEffectSelectionUI()
    this._syncEffectPanelUI()
    this._syncBeautyPanelUI()

    try {
      await this._applySelectedEffect()
    } catch (e) {
      console.error("[ivs-publisher] selected effect apply failed", e)

      this._selectedEffect = previousEffect

      if (this._selectedEffect !== "beauty") {
        this.closeBeautyPanel()
      }

      this._syncEffectSelectionUI()
      this._syncEffectPanelUI()
      this._syncBeautyPanelUI()
      this._setError("加工モードの切替に失敗しました。")
    }
  }

  async openBeautyPanel() {
    if (!this._canOpenBeautyPanel()) return

    await this._ensureInitialBeautyStateLoaded()

    this.closeEffectPanel()
    this._beautyPanelOpen = true
    this._syncBeautySliderFromState()
    this._syncBeautyPanelUI()
  }

  closeBeautyPanel() {
    this._beautyPanelOpen = false
    this._syncBeautyPanelUI()
  }

  closeBeautyPanelOnBackdrop(event) {
    if (!this.hasBeautyOverlayTarget) return
    if (event.target !== this.beautyOverlayTarget) return
    this.closeBeautyPanel()
  }

  selectBeautyControl(event) {
    const control = event.currentTarget?.dataset?.beautyControl
    if (!this._beautyControlConfig(control)) return

    this._selectedBeautyControl = control
    this._syncBeautySliderFromState()
    this._syncBeautyPanelUI()
  }

  async onBeautySliderInput(event) {
    await this._ensureInitialBeautyStateLoaded()

    const value = Number(event.target.value)
    const control = this._selectedBeautyControl

    try {
      if (control === "softlight") {
        await this.setSoftlightStrength(value)
      } else if (control === "face") {
        await this.setFaceNarrowing(value)
      } else if (control === "eye_rounding") {
        await this.setEyeRounding(value)
      } else if (control === "eye_enlargement") {
        await this.setEyeEnlargement(value)
      } else if (control === "nose") {
        await this.setNoseLength(value)
      } else if (control === "lips_size") {
        await this.setLipsSize(value)
      } else if (control === "lips_mouth_size") {
        await this.setLipsMouthSize(value)
      }

      this._syncBeautySliderFromState()
    } catch (e) {
      console.error("[ivs-publisher] beauty slider update failed", e)
      this._setError("Beauty 設定の反映に失敗しました。")
    }
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
      targetVideoSource = "processed"
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

    if (source === "processed") {
      await this._beautyProvider.ensurePublishTrack()

      const providerTrack = this._beautyProvider.videoTrack
      const providerStageStream = this._beautyProvider.stageStream

      if (!providerTrack || !providerStageStream) {
        throw new Error("provider_publish_track_unavailable")
      }

      this._currentVideoStageStream = providerStageStream
      this._publishedVideoTrack = providerTrack
      this._publishedVideoSource = "processed"
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

  _createBeautyProvider() {
    const provider = this.providerValue || "banuba"

    if (provider === "banuba") {
      return new BanubaProvider(this)
    }

    if (provider === "deepar") {
      return new DeepARProvider(this)
    }

    throw new Error(`Unknown beauty provider: ${provider}`)
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
    if (this._previewOnly) return

    this._clearError()

    try {
      await this._beautyProvider.ensureInitialBeautyStateLoaded()
      await this._beautyProvider.start()
      await this._beautyProvider.ensurePublishTrack()

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

  _shouldAutoResumeOnEntry() {
    if (!this.autoResumeOnEntryValue) return false
    if (this._autoResumeAttempted) return false
    if (this._stage || this._broadcasting) return false
    return true
  }

  async _tryAutoResumeOnEntry() {
    if (!this._shouldAutoResumeOnEntry()) return

    this._autoResumeAttempted = true
    await this.startBroadcast({ autoResume: true })
  }

  _applyBeautyConfig() {
    try {
      return this._beautyProvider.updateBeauty()
    } catch (e) {
      console.error("[ivs-publisher] apply beauty config failed", e)
      this._setError("Beauty 設定の反映に失敗しました。")
      throw e
    }
  }

  _applySelectedEffect() {
    return this._beautyProvider.applyEffect()
  }

  _ensureInitialBeautyStateLoaded() {
    return this._beautyProvider.ensureInitialBeautyStateLoaded()
  }

  setBeautyEnabled(value) {
    this._beautyState.beautyEnabled = !!value
    return this._applyBeautyConfig()
  }

  setSoftlightStrength(value) {
    this._beautyState.softlightStrength = this._clampNumber(value, 0, 1, this._beautyState.softlightStrength)
    return this._applyBeautyConfig()
  }

  setFaceNarrowing(value) {
    this._beautyState.faceNarrowing = this._clampNumber(value, 0, 1, this._beautyState.faceNarrowing)
    return this._applyBeautyConfig()
  }

  setEyeRounding(value) {
    this._beautyState.eyeRounding = this._clampNumber(value, 0, 1, this._beautyState.eyeRounding)
    return this._applyBeautyConfig()
  }

  setEyeEnlargement(value) {
    this._beautyState.eyeEnlargement = this._clampNumber(value, 0, 1, this._beautyState.eyeEnlargement)
    return this._applyBeautyConfig()
  }

  setLipsSize(value) {
    this._beautyState.lipsSize = this._clampNumber(value, -1, 1, this._beautyState.lipsSize)
    return this._applyBeautyConfig()
  }

  setLipsMouthSize(value) {
    this._beautyState.lipsMouthSize = this._clampNumber(value, -1, 1, this._beautyState.lipsMouthSize)
    return this._applyBeautyConfig()
  }

  setNoseLength(value) {
    this._beautyState.noseLength = this._clampNumber(value, -1, 1, this._beautyState.noseLength)
    return this._applyBeautyConfig()
  }

  getBeautyState() {
    return { ...this._beautyState }
  }

  _clampNumber(value, min, max, fallback) {
    const num = Number(value)
    if (!Number.isFinite(num)) return fallback
    return Math.min(max, Math.max(min, num))
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

  _beautyControlConfig(control = this._selectedBeautyControl) {
    const configs = {
      softlight: {
        label: "美白",
        min: 0,
        max: 1,
        step: 0.01,
        value: () => this._beautyState.softlightStrength,
      },
      face: {
        label: "輪郭",
        min: 0,
        max: 1,
        step: 0.01,
        value: () => this._beautyState.faceNarrowing,
      },
      eye_rounding: {
        label: "目の丸み",
        min: 0,
        max: 1,
        step: 0.01,
        value: () => this._beautyState.eyeRounding,
      },
      eye_enlargement: {
        label: "目の拡大",
        min: 0,
        max: 1,
        step: 0.01,
        value: () => this._beautyState.eyeEnlargement,
      },
      nose: {
        label: "鼻の長さ",
        min: -1,
        max: 1,
        step: 0.01,
        value: () => this._beautyState.noseLength,
      },
      lips_size: {
        label: "唇サイズ",
        min: -1,
        max: 1,
        step: 0.01,
        value: () => this._beautyState.lipsSize,
      },
      lips_mouth_size: {
        label: "口サイズ",
        min: -1,
        max: 1,
        step: 0.01,
        value: () => this._beautyState.lipsMouthSize,
      },
    }

    return configs[control] || null
  }

  _canUseEffectUI() {
    return this._broadcasting || this._previewOnly || this._boothStatus === "standby"
  }

  _canOpenBeautyPanel() {
    return this.providerValue === "banuba" &&
          this._canUseEffectUI() &&
          this._selectedEffect === "beauty"
  }

  _effectOptionInputs() {
    if (!this.hasEffectPanelTarget) return []

    return Array.from(
      this.effectPanelTarget.querySelectorAll("input[type='radio'][name='cast_live_effect_mode']")
    )
  }

  _effectOptionValues() {
    return this._effectOptionInputs()
      .map((input) => input.value)
      .filter((value) => value)
  }

  _selectedEffectInput() {
    return this._effectOptionInputs().find((input) => input.value === this._selectedEffect) || null
  }

  _isSelectableEffect(value) {
    return this._effectOptionValues().includes(value)
  }

  _shouldShowBeautyAdjustBtn() {
    return this.providerValue === "banuba" &&
          this._canUseEffectUI() &&
          this._selectedEffect === "beauty"
  }

  _syncEffectSelectionUI() {
    if (!this.hasEffectPanelTarget) return

    const inputs = this.effectPanelTarget.querySelectorAll("input[type='radio'][name='cast_live_effect_mode']")
    inputs.forEach((input) => {
      input.checked = input.value === this._selectedEffect
    })
  }

  _syncBeautyAdjustButtonVisibility() {
    if (!this.hasBeautyAdjustBtnTarget) return

    const visible = this._shouldShowBeautyAdjustBtn()

    this.beautyAdjustBtnTarget.classList.toggle("d-none", !visible)
    this.beautyAdjustBtnTarget.disabled = !visible
    this.beautyAdjustBtnTarget.classList.toggle("is-active", visible && this._beautyPanelOpen)
    this.beautyAdjustBtnTarget.setAttribute(
      "aria-expanded",
      visible && this._beautyPanelOpen ? "true" : "false"
    )

    if (this._lastBeautyAdjustBtnVisible !== visible) {
      console.log("[ivs-publisher] beautyAdjustBtnVisible:", visible)
      this._lastBeautyAdjustBtnVisible = visible
    }

    if (!visible && this._beautyPanelOpen) {
      this._beautyPanelOpen = false
    }
  }

  _syncEffectPanelUI() {
    const canUseEffectUI = this._canUseEffectUI()

    if (this.hasEffectOverlayTarget) {
      const visible = this._effectPanelOpen && canUseEffectUI
      this.effectOverlayTarget.classList.toggle("d-none", !visible)
    }

    if (this.hasEffectOpenBtnTarget) {
      this.effectOpenBtnTarget.disabled = !canUseEffectUI
      this.effectOpenBtnTarget.classList.toggle("is-active", this._effectPanelOpen)
      this.effectOpenBtnTarget.setAttribute(
        "aria-expanded",
        this._effectPanelOpen ? "true" : "false"
      )
    }

    this._syncBeautyAdjustButtonVisibility()
  }

  _syncBeautySliderFromState() {
    if (!this.hasBeautySliderTarget) return

    const config = this._beautyControlConfig()
    if (!config) return

    const currentValue = this._clampNumber(
      config.value(),
      config.min,
      config.max,
      config.min
    )

    this.beautySliderTarget.min = String(config.min)
    this.beautySliderTarget.max = String(config.max)
    this.beautySliderTarget.step = String(config.step)
    this.beautySliderTarget.value = String(currentValue)

    if (this.hasBeautyLabelTarget) {
      this.beautyLabelTarget.textContent = config.label
    }

    if (this.hasBeautyValueTarget) {
      this.beautyValueTarget.textContent = currentValue.toFixed(2)
    }
  }

  _syncBeautyPanelUI() {
    const canUseBeauty = this._canOpenBeautyPanel()

    if (this.hasBeautyOverlayTarget) {
      const visible = this._beautyPanelOpen && canUseBeauty
      this.beautyOverlayTarget.classList.toggle("d-none", !visible)
    }

    if (this.hasBeautyAdjustBtnTarget) {
      this.beautyAdjustBtnTarget.classList.toggle("is-active", canUseBeauty && this._beautyPanelOpen)
      this.beautyAdjustBtnTarget.setAttribute(
        "aria-expanded",
        canUseBeauty && this._beautyPanelOpen ? "true" : "false"
      )
    }

    if (!this.hasBeautyPanelTarget) return

    const buttons = this.beautyPanelTarget.querySelectorAll("[data-beauty-control]")
    buttons.forEach((button) => {
      const isActive = button.dataset.beautyControl === this._selectedBeautyControl
      button.classList.toggle("is-active", isActive)
      button.setAttribute("aria-pressed", isActive ? "true" : "false")
    })
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
    return this._beautyProvider.start()
  }

  _ensureBanubaPublishTrack() {
    return this._beautyProvider.ensurePublishTrack()
  }

  _destroyBanubaPlayer() {
    return this._beautyProvider.stop()
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
      const visible = this._broadcasting && this._boothStatus !== "away"
      this.cameraOffBtnTarget.disabled = !canToggleCamera || this._boothStatus === "away"
      this.cameraOffBtnTarget.classList.toggle("d-none", !visible)
    }

    if (this.hasCameraOnBtnTarget) {
      const visible = this._broadcasting && this._boothStatus === "away"
      this.cameraOnBtnTarget.disabled = !canToggleCamera || this._boothStatus !== "away"
      this.cameraOnBtnTarget.classList.toggle("d-none", !visible)
    }

    syncMicUI(this)

    if (this.hasMicBtnTarget) {
      this.micBtnTarget.classList.toggle("d-none", !this._broadcasting)
    }

    if (this.hasSummaryPanelTarget) {
      const visible = (this._boothStatus === "standby") && !this._broadcasting
      this.summaryPanelTarget.classList.toggle("d-none", !visible)
    }

    if (this.hasStartBtnTarget) {
      const normal = this.startBtnTarget.dataset.labelNormal || "配信開始"
      const resume = this.startBtnTarget.dataset.labelResume || "配信に戻る"
      const label = this.startBtnTarget.querySelector(".app-footer-nav-label")

      if (label) {
        label.textContent = this._resumable ? resume : normal
      }
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
      const visible = this._broadcasting || this._boothStatus === "standby" || this._previewOnly
      this.opsPanelTarget.classList.toggle("d-none", !visible)
    }

    this._syncEffectSelectionUI()
    this._syncEffectPanelUI()
    this._syncBeautyPanelUI()
  }

  _applyCurrentMode() {
    applyCurrentMode(this)
  }

  _patchBroadcastStartedAt() {
    return patchBroadcastStartedAt(this)
  }
}
