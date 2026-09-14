const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")
const { randomUUID } = require("node:crypto")

function deferred() {
  let resolve, reject
  const promise = new Promise((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}

async function until(check) {
  for (let i = 0; i < 100; i++) {
    if (check()) return
    await new Promise(resolve => setImmediate(resolve))
  }
  assert.fail("expected asynchronous boundary was not reached")
}

function fixture(options = {}) {
  const stages = [], requests = []
  const records = new Map()
  let generation = 0, reloads = 0, confirms = 0
  let stateUnavailable = false, cancelPending = false
  class Stage {
    constructor(token, strategy) {
      this.token = token; this.strategy = strategy
      this.events = new Map(); this.leaves = 0
      stages.push(this)
    }
    on(event, callback) {
      if (!this.events.has(event)) this.events.set(event, new Set())
      this.events.get(event).add(callback)
    }
    off(event, callback) { this.events.get(event)?.delete(callback) }
    emit(event, ...args) { for (const callback of [...(this.events.get(event) || [])]) callback(...args) }
    join() { return options.join?.(this) || Promise.resolve() }
    leave() { this.leaves++; this.emit("left") }
    publish(isLocal = true) { this.emit("publish", { isLocal }, "published") }
  }
  const sdk = {
    Stage, LocalStageStream: class { constructor(track) { this.track = track } }, SubscribeType: { NONE: "none" },
    StageEvents: { STAGE_CONNECTION_STATE_CHANGED: "connection", STAGE_PARTICIPANT_PUBLISH_STATE_CHANGED: "publish", STAGE_LEFT: "left" },
    StageParticipantPublishState: { PUBLISHED: "published" },
  }
  const response = (body, status = 200) => ({ ok: status < 400, status, json: async () => structuredClone(body) })
  const context = vm.createContext({
    console: { log() {}, warn() {} }, URL, crypto: { randomUUID }, Controller: class {}, syncMicUI() {},
    window: { IVSBroadcastClient: sdk, location: { origin: "https://example.test", reload() { reloads++ } } },
    document: { querySelector: () => ({ content: "csrf" }), removeEventListener() {} },
    fetch: async (url, request) => {
      const route = new URL(url, "https://example.test")
      const params = request.body ? JSON.parse(request.body) : Object.fromEntries(route.searchParams)
      requests.push({ path: route.pathname, params, method: request.method })
      if (route.pathname === "/token") {
        if (options.tokenRejected) return response({ error: "publisher_in_use", message: "開始処理中です" }, 409)
        assert.equal(params.expected_generation, generation)
        generation++
        const record = { request_id: params.request_id, generation, current_generation: generation, state: "issued", booth_status: "standby", stream_session_id: 7 }
        records.set(params.request_id, record)
        if (options.tokenResponse) await options.tokenResponse.promise
        if (options.lostTokenResponse) throw new Error("network")
        return response({ ...record, participant_token: "test-token", participant_id: "test-participant" })
      }
      const record = records.get(params.request_id)
      if (route.pathname === "/state") {
        if (stateUnavailable) throw new Error("network")
        return record ? response(record) : response({ error: "stale_publisher_request" }, 409)
      }
      if (route.pathname === "/confirm") {
        confirms++
        assert.equal(params.generation, record.generation)
        if (options.confirmFails) return response({ error: "publisher_state_unavailable", message: "確認できません" }, 503)
        Object.assign(record, { state: "confirmed", booth_status: "live", actual_publisher_user_id: 22, broadcast_started_at: "2026-09-14T01:00:00Z" })
        if (options.lostConfirmationResponse) throw new Error("network")
        return response(record)
      }
      if (route.pathname === "/cancel") {
        assert.equal(params.generation, record.generation)
        if (record.state !== "confirmed") {
          if (record.state === "issued") generation++
          Object.assign(record, { state: cancelPending ? "cancel_pending" : "cancelled", current_generation: generation, disconnect_pending: cancelPending })
        }
        return response(record, cancelPending ? 202 : 200)
      }
      assert.fail(`unexpected request ${route.pathname}`)
    },
  })
  for (const filename of ["ivs_publisher/api_client.js", "ivs_publisher/media_state.js", "ivs_publisher/publisher_connection.js", "ivs_publisher_controller.js"]) {
    const source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers", filename), "utf8")
      .replace(/^import .*$/gm, "")
      .replace("export default class extends Controller", "globalThis.PublisherController = class extends Controller")
      .replace(/export (async function|function|class) /g, "$1 ")
    vm.runInContext(source, context, { filename })
  }
  const controller = Object.assign(new context.PublisherController(), {
    publisherControlValue: true, publisherGenerationValue: 0, streamSessionIdValue: 7,
    tokenUrlValue: "/token", publisherStateUrlValue: "/state", startBroadcastUrlValue: "/confirm", cancelBroadcastUrlValue: "/cancel",
    hasTokenUrlValue: true, providerValue: "banuba", banubaClientTokenValue: "test-config", _state: "idle", _mode: "normal", _boothStatus: "standby",
    _beautyProvider: { ensureInitialBeautyStateLoaded: async () => {}, start: async () => {}, ensurePublishTrack: async () => {}, videoTrack: { kind: "video" }, stageStream: { track: "processed" } },
    _audioTrack: { kind: "audio" }, _ensureAudioTrack: async () => {},
    _syncUI() {}, _applyManualMicState() {}, _applyCurrentMode() {}, closeEffectPanel() {}, closeBeautyPanel() {},
    _syncEffectSelectionUI() {}, _syncEffectPanelUI() {}, _syncBeautyPanelUI() {},
    _reloadMetaDisplay: async () => {}, _clearError() { this.error = null }, _setError(message) { this.error = message }, _humanizeError: error => error.message,
    async _cleanupMediaAndCanvas() { this.mediaCleanups = (this.mediaCleanups || 0) + 1 },
  })
  return { controller, stages, requests, records, syncActualUI: () => context.PublisherController.prototype._syncUI.call(controller),
    get reloads() { return reloads }, get confirms() { return confirms },
    set stateUnavailable(value) { stateUnavailable = value }, set cancelPending(value) { cancelPending = value } }
}

test("S03 join completion and a remote published event cannot confirm; local published confirms once with identity and processed video/audio", async () => {
  const f = fixture()
  const starting = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(f.confirms, 0)
  assert.equal(f.controller._broadcasting, undefined)
  f.stages[0].publish(false)
  assert.equal(f.confirms, 0)
  const streams = f.stages[0].strategy.stageStreamsToPublish()
  assert.equal(streams[0], f.controller._beautyProvider.stageStream)
  assert.equal(streams[1].track, f.controller._audioTrack)
  f.stages[0].publish()
  await starting
  f.stages[0].publish()
  assert.equal(f.confirms, 1)
  assert.equal(f.controller._broadcasting, true)
  assert.equal(f.controller.publisherGenerationValue, 1)
  assert.equal(f.stages[0].leaves, 0)
  assert.deepEqual(f.requests.map(r => r.path), ["/token", "/confirm"])
  assert.equal(f.requests[1].params.request_id, f.requests[0].params.request_id)
})

test("S04 camera failure before token issuance keeps preparation without inventing a cancellation", async () => {
  const f = fixture()
  f.controller._beautyProvider.start = async () => { throw new Error("camera failed") }
  await f.controller.startBroadcast()
  assert.equal(f.requests.length, 0)
  assert.equal(f.stages.length, 0)
  assert.equal(f.controller._publisherRecoveryPending, false)
  assert.equal(f.controller.publisherGenerationValue, 0)
})

test("S04 join failure leaves that SDK and cancels the saved request; retry uses a new UUID and returned generation", async () => {
  let fail = true
  const f = fixture({ join: () => fail ? Promise.reject(new Error("join failed")) : Promise.resolve() })
  await f.controller.startBroadcast()
  assert.ok(f.stages[0].leaves > 0)
  assert.equal(f.controller._stage, null)
  assert.equal(f.controller._publisherRecoveryPending, false)
  assert.equal(f.controller.publisherGenerationValue, 2)
  assert.deepEqual(f.requests.map(r => r.path), ["/token", "/state", "/cancel"])
  fail = false
  const retry = f.controller.startBroadcast()
  await until(() => f.stages.length === 2)
  f.stages[1].publish()
  await retry
  assert.notEqual(f.requests[0].params.request_id, f.requests[3].params.request_id)
  assert.equal(f.requests[3].params.expected_generation, 2)
  assert.equal(f.controller._broadcasting, true)
})

test("S05 token response loss queries and cancels its identity without blindly minting a second token", async () => {
  const f = fixture({ lostTokenResponse: true })
  await f.controller.startBroadcast()
  assert.deepEqual(f.requests.map(r => r.path), ["/token", "/state", "/cancel"])
  assert.equal(f.stages.length, 0)
  assert.equal(f.controller.publisherGenerationValue, 2)
  assert.equal(f.controller._publisherRecoveryPending, false)
})

test("S05 confirmation response loss retains the same SDK after recovering the committed result", async () => {
  const f = fixture({ lostConfirmationResponse: true })
  const starting = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await starting
  assert.deepEqual(f.requests.map(r => r.path), ["/token", "/confirm", "/state"])
  assert.equal(f.controller._stage, f.stages[0])
  assert.equal(f.stages[0].leaves, 0)
  assert.equal(f.controller._broadcasting, true)
})

test("S05 DB confirmation failure leaves SDK and pending external cancellation blocks new starts until manual retry succeeds", async () => {
  const f = fixture({ confirmFails: true })
  f.cancelPending = true
  const starting = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await starting
  assert.ok(f.stages[0].leaves > 0)
  assert.equal(f.controller._publisherRecoveryPending, true)
  assert.match(f.controller.error, /確認待ち/)
  f.controller.closeError()
  assert.match(f.controller.error, /確認待ち/)
  await f.controller.startBroadcast()
  assert.equal(f.requests.filter(r => r.path === "/token").length, 1)
  f.cancelPending = false
  await f.controller.retryPublisherRecovery()
  assert.equal(f.controller._publisherRecoveryPending, false)
  assert.equal(f.controller.error, null)
  assert.equal(f.controller.publisherGenerationValue, 2)
})

test("S06 unknown result keeps SDK identity, leaves locally, and retries only the saved request", async () => {
  const f = fixture({ confirmFails: true })
  f.stateUnavailable = true
  const starting = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await starting
  assert.equal(f.controller._publisherRecoveryPending, true)
  assert.equal(f.controller._publisherAttempt.stage, f.stages[0])
  assert.ok(f.stages[0].leaves > 0)
  await f.controller.startBroadcast()
  assert.equal(f.stages.length, 1)
  f.stateUnavailable = false
  await f.controller.retryPublisherRecovery()
  assert.equal(f.controller._publisherRecoveryPending, false)
  assert.equal(f.requests.at(-1).params.request_id, f.requests[0].params.request_id)
})

test("R03 navigation while join is pending leaves the captured old SDK even when it completes after a new screen connects", async () => {
  const joining = deferred()
  const f = fixture({ join: stage => stage === f.stages[0] ? joining.promise : Promise.resolve() })
  const starting = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  const oldStage = f.stages[0]
  f.controller.disconnect()
  const replacement = { leaves: 0, leave() { this.leaves++ } }
  // 同じStimulusインスタンスが再接続した時の所有者交代を再現する。
  f.controller._publisherAttempt = { newScreen: true }
  f.controller._stage = replacement
  joining.resolve()
  await starting
  oldStage.publish()
  oldStage.emit("connection", "connected")
  assert.ok(oldStage.leaves >= 2)
  assert.equal(replacement.leaves, 0)
  assert.equal(f.controller._stage, replacement)
  assert.equal(f.controller.mediaCleanups, undefined)
  assert.equal(f.confirms, 0)
  assert.equal(oldStage.strategy.shouldPublishParticipant(), false)
  assert.equal(oldStage.strategy.stageStreamsToPublish().length, 0)
  assert.equal(f.requests.at(-1).path, "/cancel")
})

test("R03 cancellation during token request handles the late response and never creates a SDK", async () => {
  const tokenResponse = deferred()
  const f = fixture({ tokenResponse })
  const starting = f.controller.startBroadcast()
  await until(() => f.requests.length === 1)
  const cancelling = f.controller.endBroadcast()
  tokenResponse.resolve()
  await Promise.all([starting, cancelling])
  assert.equal(f.stages.length, 0)
  assert.equal(f.confirms, 0)
  assert.equal(f.requests.at(-1).path, "/cancel")
  assert.equal(f.controller._publisherRecoveryPending, false)
})

test("S02 losing start never cancels another request and stale recovery asks to reload", async () => {
  const f = fixture({ tokenRejected: true })
  await f.controller.startBroadcast()
  assert.deepEqual(f.requests.map(r => r.path), ["/token", "/state"])
  assert.equal(f.controller._publisherRecoveryPending, true)
  assert.match(f.controller.error, /読み込み直し/)
  await f.controller.retryPublisherRecovery()
  assert.equal(f.reloads, 1)
})

test("S04/S06 pending confirmation exposes cancellation; unresolved recovery keeps retry visible and new starts disabled", async () => {
  const f = fixture({ confirmFails: true })
  function button() {
    const classes = new Set()
    return { dataset: {}, label: { textContent: "" }, querySelector() { return this.label },
      classList: { add: value => classes.add(value), remove: value => classes.delete(value),
        toggle: (value, on) => on ? classes.add(value) : classes.delete(value), contains: value => classes.has(value) } }
  }
  Object.assign(f.controller, { hasStartBtnTarget: true, hasEndBtnTarget: true, hasRetryPublisherBtnTarget: true, hasErrorCloseBtnTarget: true,
    startBtnTarget: button(), endBtnTarget: button(), retryPublisherBtnTarget: button(), errorCloseBtnTarget: button() })
  const starting = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.syncActualUI()
  assert.equal(f.controller.endBtnTarget.label.textContent, "開始を取り消す")
  assert.equal(f.controller.startBtnTarget.classList.contains("d-none"), true)
  f.cancelPending = true
  f.stages[0].publish()
  await starting
  f.syncActualUI()
  assert.equal(f.controller.startBtnTarget.disabled, true)
  assert.equal(f.controller.retryPublisherBtnTarget.classList.contains("d-none"), false)
  assert.equal(f.controller.retryPublisherBtnTarget.disabled, false)
  assert.equal(f.controller.errorCloseBtnTarget.classList.contains("d-none"), true)
})
