import { issuePublisherToken, confirmPublisher, readPublisherState, cancelPublisher } from "controllers/ivs_publisher/api_client"

// 1回の開始操作が所有する要求とSDKを保持する。画面の最新Stageへ読み替えない。
export class PublisherConnection {
  constructor(ctx) {
    this.ctx = ctx
    this.requestId = crypto.randomUUID()
    this.expectedGeneration = ctx.publisherGenerationValue
    this.generation = null
    this.stage = null
    this.state = "preparing"
    this.invalidated = false
    this.left = false
    this.tokenRequested = false
  }

  isCurrent() {
    return this.ctx._publisherAttempt === this && !this.invalidated
  }

  assertCurrent() {
    if (!this.isCurrent()) throw new Error("publisher_attempt_cancelled")
  }

  async token() {
    this.assertCurrent()
    this.tokenRequested = true
    const result = await issuePublisherToken(this.ctx, this)
    this.acceptState(result)
    if (!result.participant_token) throw new Error("publisher_token_missing")
    return result.participant_token
  }

  watchPublish(stage, sdk) {
    this.stage = stage
    const event = sdk.StageEvents?.STAGE_PARTICIPANT_PUBLISH_STATE_CHANGED
    const published = sdk.StageParticipantPublishState?.PUBLISHED
    if (!event || !published) throw new Error("IVS SDK publish events not loaded")

    const promise = new Promise((resolve, reject) => {
      const onPublished = (participant, state) => {
        if (!this.isCurrent() || !participant?.isLocal || state !== published) return
        this.published = true
        this.stopWatching()
        resolve()
      }
      const onLeft = () => {
        this.stopWatching()
        reject(new Error("publisher_left_before_confirmation"))
      }
      this.stopWatching = () => {
        stage.off(event, onPublished)
        if (sdk.StageEvents.STAGE_LEFT) stage.off(sdk.StageEvents.STAGE_LEFT, onLeft)
        this.cancelPublishWait = null
      }
      this.cancelPublishWait = onLeft
      stage.on(event, onPublished)
      if (sdk.StageEvents.STAGE_LEFT) stage.on(sdk.StageEvents.STAGE_LEFT, onLeft)
    })
    // joinの完了を待つ間の退出も、未処理のPromise拒否にしない。
    promise.catch(() => {})
    return promise
  }

  async confirm() {
    this.assertCurrent()
    if (!this.published) throw new Error("publisher_not_published")
    this.acceptState(await confirmPublisher(this.ctx, this))
    if (this.state !== "confirmed") throw new Error("publisher_confirmation_missing")
  }

  acceptState(result) {
    if (result.request_id !== this.requestId || !Number.isSafeInteger(result.generation) || result.generation < 1 ||
        (this.generation !== null && this.generation !== result.generation) || !Number.isSafeInteger(result.current_generation)) {
      throw new Error("publisher_response_mismatch")
    }
    this.generation = result.generation
    this.currentGeneration = result.current_generation
    this.state = result.state
    this.result = result
  }

  leave() {
    this.left = true
    this.cancelPublishWait?.()
    const stage = this.stage
    if (!stage) return
    const leaveStage = () => { try { stage.leave() } catch (_) {} }
    leaveStage()
    // join中の退出にSDKが追いつかなかった場合も、同じインスタンスだけを退出する。
    this.joinPromise?.then(leaveStage, leaveStage)
  }

  invalidate() {
    this.invalidated = true
    this.leave()
  }

  async recover() {
    if (!this.tokenRequested) {
      this.state = "cancelled"
      this.currentGeneration = this.expectedGeneration
      return
    }
    try {
      this.acceptState(await readPublisherState(this.ctx, this))
      if (this.state === "issued" || this.state === "cancel_pending") {
        this.leave()
        this.acceptState(await cancelPublisher(this.ctx, this))
      }
      if (this.state !== "confirmed") this.leave()
    } catch (error) {
      this.leave()
      // 古い画面や権限喪失の場合は、別要求を推測して取消・再発行しない。
      this.state = error.status === 403 || error.code === "stale_publisher_request" ? "stale" : "pending"
    }
  }

  get pending() {
    return this.state === "pending" || this.state === "cancel_pending"
  }

  get needsReload() {
    return ["stale", "superseded", "ended"].includes(this.state)
  }
}
