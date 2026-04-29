import {
  applyDeepARBeautyConfig,
  applyDeepAREffect,
  destroyDeepAR,
  ensureDeepARPublishTrack,
  ensureDeepARStarted,
  ensureInitialDeepARBeautyStateLoaded,
} from "controllers/ivs_publisher/deepar_session"

export class DeepARProvider {
  constructor(ctx) {
    this.ctx = ctx
  }

  start() {
    return ensureDeepARStarted(this.ctx)
  }

  ensurePublishTrack() {
    return ensureDeepARPublishTrack(this.ctx)
  }

  stop() {
    return destroyDeepAR(this.ctx)
  }

  applyEffect(effect = null) {
    return applyDeepAREffect(this.ctx, effect)
  }

  updateBeauty() {
    return applyDeepARBeautyConfig(this.ctx)
  }

  ensureInitialBeautyStateLoaded() {
    return ensureInitialDeepARBeautyStateLoaded(this.ctx)
  }

  get videoTrack() {
    return this.ctx._deepARVideoTrack
  }

  get stageStream() {
    return this.ctx._deepARStageStream
  }

  get sourceName() {
    return "deepar"
  }
}
