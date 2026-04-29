import {
  applyBeautyConfig,
  applySelectedEffect,
  destroyBanubaPlayer,
  ensureBanubaPublishTrack,
  ensureBanubaStarted,
  ensureInitialBeautyStateLoaded,
} from "controllers/ivs_publisher/banuba_session"

export class BanubaProvider {
  constructor(ctx) {
    this.ctx = ctx
  }

  start() {
    return ensureBanubaStarted(this.ctx)
  }

  ensurePublishTrack() {
    return ensureBanubaPublishTrack(this.ctx)
  }

  stop() {
    return destroyBanubaPlayer(this.ctx)
  }

  applyEffect() {
    return applySelectedEffect(this.ctx)
  }

  updateBeauty() {
    return applyBeautyConfig(this.ctx)
  }

  ensureInitialBeautyStateLoaded() {
    return ensureInitialBeautyStateLoaded(this.ctx)
  }

  get videoTrack() {
    return this.ctx._banubaVideoTrack
  }

  get stageStream() {
    return this.ctx._banubaStageStream
  }

  get sourceName() {
    return "banuba"
  }
}
