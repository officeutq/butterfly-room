export class DeepARProvider {
  constructor(ctx) {
    this.ctx = ctx
    this._deepAR = null
    this._started = false
    this._stream = null
    this._videoTrack = null
    this._stageStream = null
  }

  async start() {
    if (this._started && this._deepAR) return

    if (!this.ctx.deeparLicenseKeyValue) {
      throw new Error("deepar_license_key_missing")
    }

    if (!window.deepar || typeof window.deepar.initialize !== "function") {
      throw new Error("deepar_sdk_not_loaded")
    }

    if (!this.ctx.hasBanubaSurfaceTarget) {
      throw new Error("deepar_surface_missing")
    }

    const effect = this.ctx.deeparDefaultEffectUrlValue || ""

    const deepAR = await window.deepar.initialize({
      licenseKey: this.ctx.deeparLicenseKeyValue,
      previewElement: this.ctx.banubaSurfaceTarget,
      effect,
      rootPath: this.ctx.deeparRootPathValue || "/deepar",
    })

    this._deepAR = deepAR
    this._started = true

    await this._nextFrame()
    await this._nextFrame()
  }

  async ensurePublishTrack() {
    await this.start()

    if (this._videoTrack && this._stageStream) return

    const node = await this._findRenderableNode()
    const stream = node.captureStream(30)
    const track = stream.getVideoTracks()[0] || null

    if (!track) {
      throw new Error("deepar_publish_track_unavailable")
    }

    this._stream = stream
    this._videoTrack = track

    const { LocalStageStream } = window.IVSBroadcastClient || {}
    this._stageStream = track && LocalStageStream ? new LocalStageStream(track) : null
  }

  async stop() {
    if (this._stream) {
      try {
        this._stream.getTracks().forEach((track) => track.stop())
      } catch (_) {}
    }

    this._stream = null
    this._videoTrack = null
    this._stageStream = null

    if (this._deepAR && typeof this._deepAR.shutdown === "function") {
      try {
        this._deepAR.shutdown()
      } catch (_) {}
    }

    this._deepAR = null
    this._started = false

    if (this.ctx.hasBanubaSurfaceTarget) {
      this.ctx.banubaSurfaceTarget.innerHTML = ""
    }
  }

  async applyEffect(effect = null) {
    if (!this._deepAR) return

    const effectUrl =
      effect?.url ||
      effect?.effectUrl ||
      this.ctx.deeparDefaultEffectUrlValue ||
      ""

    if (!effectUrl) return

    if (typeof this._deepAR.switchEffect !== "function") {
      throw new Error("deepar_switch_effect_not_available")
    }

    await this._deepAR.switchEffect(effectUrl)
  }

  updateBeauty() {
    // DeepAR Beauty 制御は後続Issueで実装する
    return Promise.resolve()
  }

  ensureInitialBeautyStateLoaded() {
    // 既存 controller との互換用。DeepAR 側の初期Beauty読込は後続Issueで扱う
    return Promise.resolve({})
  }

  get videoTrack() {
    return this._videoTrack
  }

  get stageStream() {
    return this._stageStream
  }

  get sourceName() {
    return "deepar"
  }

  async _findRenderableNode() {
    const timeoutMs = 5000
    const startAt = Date.now()

    while ((Date.now() - startAt) < timeoutMs) {
      const node =
        this._deepAR?.canvas ||
        this.ctx.banubaSurfaceTarget?.querySelector("canvas, video")

      if (node && typeof node.captureStream === "function") {
        return node
      }

      await this._nextFrame()
    }

    throw new Error("deepar_render_node_not_found")
  }

  _nextFrame() {
    return new Promise((resolve) => requestAnimationFrame(() => resolve()))
  }
}
