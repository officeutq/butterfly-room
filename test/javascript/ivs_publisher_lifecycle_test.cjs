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
  let generation = options.initialGeneration || 0, reloads = 0, confirms = 0, statusCalls = 0, finishes = 0
  const visits = []
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
    window: { IVSBroadcastClient: sdk, location: { origin: "https://example.test", reload() { reloads++ }, assign(url) { visits.push(url) } } },
    document: { querySelector: () => ({ content: "csrf" }), removeEventListener() {} },
    fetch: async (url, request) => {
      const route = new URL(url, "https://example.test")
      const params = request.body ? JSON.parse(request.body) : Object.fromEntries(route.searchParams)
      requests.push({ path: route.pathname, params, method: request.method })
      if (route.pathname === "/token") {
        if (options.tokenDisconnectPending) return response({ error: "publisher_disconnect_pending", message: "切断を確認しています" }, 202)
        if (options.tokenRejected) return response({ error: "publisher_in_use", message: "開始処理中です" }, 409)
        if (options.tokenUnavailableOnce) {
          options.tokenUnavailableOnce = false
          return response({ error: "publisher_state_unavailable", message: "以前の接続を確認できません" }, 503)
        }
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
        if (options.confirmResponse) await options.confirmResponse.promise
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
      if (route.pathname === "/status") {
        statusCalls++
        if (options.statusResponse) await options.statusResponse.promise
        if (options.statusFailureOn === statusCalls) return response({ error: "publisher_state_unavailable", message: "確認できません" }, 503)
        assert.equal(params.generation, record.generation)
        record.booth_status = params.to
        return response({ ok: true })
      }
      if (route.pathname === "/finish") {
        finishes++
        if (options.staleFinish) return response({ error: "stale_publisher_request" }, 409)
        if (options.finishResponse) await options.finishResponse.promise
        if (options.lostFinishResponse && finishes === 1) throw new Error("network")
        return response({ state: "ended", stream_session_id: 7, redirect_url: "/result/7", disconnect_pending: !!options.disconnectPending }, options.disconnectPending ? 202 : 200)
      }
      if (route.pathname === "/retry-disconnect") return response({ disconnect_pending: !!options.retryDisconnectPending })
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
    publisherControlValue: true, publisherGenerationValue: options.initialGeneration || 0, streamSessionIdValue: 7,
    tokenUrlValue: "/token", publisherStateUrlValue: "/state", startBroadcastUrlValue: "/confirm", cancelBroadcastUrlValue: "/cancel", statusUrlValue: "/status", retryPublisherDisconnectUrlValue: "/retry-disconnect",
    hasTokenUrlValue: true, providerValue: "banuba", banubaClientTokenValue: "test-config", _state: "idle", _mode: "normal", _boothStatus: "standby",
    _beautyProvider: { ensureInitialBeautyStateLoaded: async () => {}, start: async () => {}, ensurePublishTrack: async () => {}, videoTrack: { kind: "video" }, stageStream: { track: "processed" } },
    _audioTrack: { kind: "audio" }, _ensureAudioTrack: async () => {},
    _syncUI() {}, _applyManualMicState() {}, _applyCurrentMode() {}, closeEffectPanel() {}, closeBeautyPanel() {},
    _syncEffectSelectionUI() {}, _syncEffectPanelUI() {}, _syncBeautyPanelUI() {},
    _reloadMetaDisplay: async () => {}, _clearError() { this.error = null }, _setError(message) { this.error = message }, _humanizeError: error => error.message,
    async _cleanupMediaAndCanvas() { this.mediaCleanups = (this.mediaCleanups || 0) + 1 },
  })
  return { controller, stages, requests, records, syncActualUI: () => context.PublisherController.prototype._syncUI.call(controller),
    restoreAttempt: attributes => { const Connection = vm.runInContext("PublisherConnection", context); return new Connection(controller, attributes) },
    visits, get finishes() { return finishes },
    get reloads() { return reloads }, get confirms() { return confirms },
    set stateUnavailable(value) { stateUnavailable = value }, set cancelPending(value) { cancelPending = value } }
}

test("selection holds new starts and disposes preparation preview only after selection succeeds", async () => {
  const f = fixture()
  const preview = deferred()
  f.controller._previewOperation = preview.promise
  f.controller._previewOnly = true
  await f.controller.prepareSelectionSwitch()
  await f.controller.startBroadcast()
  assert.equal(f.requests.length, 0)
  assert.equal(f.controller.mediaCleanups, undefined)
  const completed = f.controller.completeSelectionSwitch()
  assert.equal(f.controller.mediaCleanups, undefined)
  preview.resolve()
  await completed
  assert.equal(f.controller.mediaCleanups, 1)
  assert.equal(f.finishes, 0)
})

test("selection failure releases the start lock and keeps the existing preparation preview", async () => {
  const f = fixture()
  f.controller._previewOnly = true
  await f.controller.prepareSelectionSwitch()
  f.controller.resumeAfterSelectionFailure()
  assert.equal(f.controller._selectionSwitchPending, false)
  assert.equal(f.controller._previewOnly, true)
  assert.equal(f.controller.mediaCleanups, undefined)
  assert.equal(f.finishes, 0)
})

test("selection cancels the same in-flight token request before allowing a different booth", async () => {
  const tokenResponse = deferred()
  const f = fixture({ tokenResponse })
  const start = f.controller.startBroadcast()
  await until(() => f.requests.length === 1)
  const switchPreparation = f.controller.prepareSelectionSwitch()
  assert.equal(f.controller._selectionSwitchPending, true)
  tokenResponse.resolve()
  await Promise.all([start, switchPreparation])
  assert.equal(f.controller._publisherAttempt.state, "cancelled")
  assert.equal(f.requests.filter(r => r.path === "/cancel").length, 1)
  assert.equal(f.confirms, 0)
  assert.equal(f.finishes, 0)
})

test("selection cannot force-end a start that was confirmed while its response was pending", async () => {
  const confirmResponse = deferred()
  const f = fixture({ confirmResponse })
  const start = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await until(() => f.confirms === 1)
  const switching = f.controller.prepareSelectionSwitch()
  confirmResponse.resolve()
  await Promise.all([start, switching])
  assert.equal(f.controller._publisherAttempt.state, "confirmed")
  assert.equal(f.controller._resumable, true)
  assert.equal(f.finishes, 0)
})

test("confirmed broadcast remains connected while the server rechecks selection against current DB state", async () => {
  const f = fixture()
  const start = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await start
  await f.controller.prepareSelectionSwitch()
  assert.equal(f.stages[0].leaves, 0)
  assert.equal(f.controller._broadcasting, true)
  assert.equal(f.finishes, 0)
})

test("selection waits for recovery when cancellation cannot be confirmed", async () => {
  const f = fixture()
  const start = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stateUnavailable = true
  await assert.rejects(f.controller.prepareSelectionSwitch(), /確認待ち/)
  await start
  assert.equal(f.controller._publisherRecoveryPending, true)
  assert.equal(f.finishes, 0)
})

test("starting during preparation preview waits for media initialization before publishing", async () => {
  const f = fixture()
  const preview = deferred()
  let starts = 0
  f.controller._beautyProvider.start = async () => { starts++; await preview.promise }
  const preparing = f.controller._startPreviewOnlyIfNeeded()
  await until(() => starts === 1)
  const starting = f.controller.startBroadcast()
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(starts, 1)
  assert.equal(f.stages.length, 0)
  assert.equal(f.requests.length, 0)
  preview.resolve()
  await preparing
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await starting
  assert.equal(f.controller._broadcasting, true)
  assert.equal(f.confirms, 1)
})

test("leaving while start waits for preview does not request a publisher token", async () => {
  const f = fixture()
  const preview = deferred()
  f.controller._previewOperation = preview.promise
  const starting = f.controller.startBroadcast()
  f.controller.disconnect()
  preview.resolve()
  await starting
  assert.equal(f.stages.length, 0)
  assert.equal(f.requests.length, 0)
})

test("E01 unstarted preparation finishes with generation zero and no participant request", async () => {
  const f = fixture()
  f.controller.finishUrlValue = "/finish"
  await f.controller.endBroadcast()
  assert.deepEqual(f.requests.map(r => r.path), ["/finish"])
  assert.equal(f.requests[0].params.generation, 0)
  assert.equal(f.requests[0].params.request_id, null)
  assert.deepEqual(f.visits, ["/result/7"])
})

test("E05 an older pending disconnect blocks token issuance and can be rechecked before starting", async () => {
  const options = { tokenDisconnectPending: true, retryDisconnectPending: true }
  const f = fixture(options)
  await f.controller.startBroadcast()
  assert.equal(f.controller._publisherRecoveryPending, true)
  assert.equal(f.stages.length, 0)
  options.retryDisconnectPending = false
  options.tokenDisconnectPending = false
  await f.controller.retryPublisherRecovery()
  assert.equal(f.controller._publisherRecoveryPending, false)
  const starting = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await starting
  assert.equal(f.controller._broadcasting, true)
  assert.equal(f.requests.filter(r => r.path === "/retry-disconnect").length, 2)
})

test("preparation hides end while start cancellation, broadcast end and resume controls remain available", () => {
  const f = fixture()
  const button = () => {
    const classes = new Set()
    const label = {}
    return { label, dataset: {}, querySelector: () => label,
      classList: { add: value => classes.add(value), remove: value => classes.delete(value), contains: value => classes.has(value),
        toggle: (value, on) => on ? classes.add(value) : classes.delete(value) } }
  }
  Object.assign(f.controller, { hasStartBtnTarget: true, hasEndBtnTarget: true, startBtnTarget: button(), endBtnTarget: button() })
  const assertControls = (startLabel, endLabel) => {
    f.syncActualUI()
    assert.equal(f.controller.startBtnTarget.classList.contains("d-none"), startLabel === null)
    assert.equal(f.controller.endBtnTarget.classList.contains("d-none"), endLabel === null)
    if (startLabel) assert.equal(f.controller.startBtnTarget.label.textContent, startLabel)
    if (endLabel) assert.equal(f.controller.endBtnTarget.label.textContent, endLabel)
  }

  assertControls("配信開始", null)

  // プレビュー待ちも含め、開始途中の取消は引き続き操作できる。
  f.controller._publisherStartOperation = Promise.resolve()
  assertControls(null, "開始を取り消す")
  f.controller._publisherStartOperation = null
  for (const state of ["starting", "joining", "confirming"]) {
    f.controller._state = state
    assertControls(null, "開始を取り消す")
  }

  Object.assign(f.controller, { _state: "live", _broadcasting: true, _resumable: true })
  for (const status of ["live", "away"]) {
    f.controller._boothStatus = status
    assertControls(null, "配信終了")
  }
  f.controller._broadcasting = false
  assertControls("配信に戻る", "配信終了")

  Object.assign(f.controller, { _state: "idle", _boothStatus: "standby", _resumable: false })
  assertControls("配信開始", null)
  f.controller.publisherControlValue = false
  assertControls("配信開始", null)
  assert.equal(f.requests.length, 0)
})

test("E05 lost end response keeps the same request, blocks start and retries that end", async () => {
  const f = fixture({ lostFinishResponse: true })
  f.controller.finishUrlValue = "/finish"
  const starting = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await starting
  const attempt = f.controller._publisherAttempt
  await f.controller.endBroadcast()
  assert.equal(f.controller._publisherRecoveryPending, true)
  assert.equal(f.controller._broadcasting, false)
  assert.ok(f.stages[0].leaves > 0)
  assert.equal(f.visits.length, 0)
  await f.controller.startBroadcast()
  assert.equal(f.stages.length, 1)
  await f.controller.retryPublisherRecovery()
  const endings = f.requests.filter(r => r.path === "/finish")
  assert.equal(endings.length, 2)
  assert.deepEqual(endings[0].params, endings[1].params)
  assert.equal(endings[0].params.request_id, attempt.requestId)
  assert.equal(endings[0].params.generation, 1)
  assert.deepEqual(f.visits, ["/result/7"])
})

test("E05 external disconnect pending still completes the end and navigates to the result", async () => {
  const f = fixture({ disconnectPending: true })
  f.controller.finishUrlValue = "/finish"
  await f.controller.endBroadcast()
  assert.deepEqual(f.visits, ["/result/7"])
  assert.equal(f.controller._boothStatus, "offline")
})

test("R03 a stale end is not rewritten to a newer request and requires reload", async () => {
  const f = fixture({ staleFinish: true })
  f.controller.finishUrlValue = "/finish"
  await f.controller.endBroadcast()
  await f.controller.retryPublisherRecovery()
  assert.equal(f.finishes, 1)
  assert.equal(f.reloads, 1)
  assert.equal(f.visits.length, 0)
})

test("R03 a late end response after leaving cannot navigate or clean up a new connection", async () => {
  const finishResponse = deferred()
  const f = fixture({ finishResponse })
  f.controller.finishUrlValue = "/finish"
  const ending = f.controller.endBroadcast()
  await until(() => f.finishes === 1)
  f.controller.disconnect()
  const replacement = { requestId: "new" }
  f.controller._publisherAttempt = replacement
  f.controller._broadcasting = true
  finishResponse.resolve()
  await ending
  assert.equal(f.controller._publisherAttempt, replacement)
  assert.equal(f.controller._broadcasting, true)
  assert.equal(f.visits.length, 0)
})

test("E05 media cleanup failure does not prevent the server end", async () => {
  const f = fixture()
  f.controller.finishUrlValue = "/finish"
  f.controller._cleanupMediaAndCanvas = async () => { throw new Error("media failed") }
  await f.controller.endBroadcast()
  assert.equal(f.finishes, 1)
  assert.deepEqual(f.visits, ["/result/7"])
})

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

test("R02 SDK automatic reconnection keeps its request; terminal leave exposes resume and a new SDK uses a new request", async () => {
  const f = fixture()
  const initial = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await initial
  const first = f.controller._publisherAttempt
  f.stages[0].emit("connection", "disconnected")
  f.stages[0].emit("connection", "connected")
  assert.equal(f.controller._publisherAttempt, first)
  assert.equal(f.requests.filter(r => r.path === "/token").length, 1)
  f.stages[0].emit("left")
  await until(() => !f.controller._publisherRecovering)
  assert.equal(f.controller._broadcasting, false)
  assert.equal(f.controller._resumable, true)
  assert.equal(f.controller._stage, null)
  const resume = f.controller.startBroadcast()
  await until(() => f.stages.length === 2)
  f.stages[1].publish()
  await resume
  assert.equal(f.controller._broadcasting, true)
  assert.notEqual(f.controller._publisherAttempt.requestId, first.requestId)
  assert.equal(f.controller.publisherGenerationValue, 2)
})

test("R02 explicit token issuance failure and missing saved request allow manual retry on the same generation without a fixed wait", async () => {
  const f = fixture({ tokenUnavailableOnce: true, initialGeneration: 1 })
  f.controller._resumable = true
  f.controller._boothStatus = "live"
  f.controller.autoResumeOnEntryValue = true
  await f.controller._tryAutoResumeOnEntry()
  assert.equal(f.controller._publisherRecoveryPending, false)
  assert.equal(f.controller._resumable, true)
  assert.equal(f.controller.publisherGenerationValue, 1)
  assert.match(f.controller.error, /復帰に失敗/)
  const retry = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await retry
  assert.equal(f.controller._broadcasting, true)
  assert.equal(f.requests.filter(r => r.path === "/token").length, 2)
})

test("R02 reload recovery uses the stored own UUID and cancels its unconfirmed request before allowing start", async () => {
  const f = fixture({ lostTokenResponse: true })
  f.stateUnavailable = true
  await f.controller.startBroadcast()
  const requestId = f.requests[0].params.request_id
  const stored = f.records.get(requestId)
  f.controller._publisherAttempt = f.restoreAttempt({ requestId, generation: stored.generation, state: "issued", tokenRequested: true })
  f.stateUnavailable = false
  await f.controller.retryPublisherRecovery()
  assert.equal(f.controller._publisherRecoveryPending, false)
  assert.equal(f.controller.publisherGenerationValue, 2)
  assert.deepEqual(f.requests.slice(-2).map(r => r.path), ["/state", "/cancel"])
  assert.equal(f.requests.at(-1).params.request_id, requestId)
  assert.equal(f.requests.filter(r => r.path === "/token").length, 1)
})

test("R01 away and return send the current identity and change media after the response", async () => {
  const f = fixture()
  const initial = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await initial
  const sources = []
  f.controller._switchPublishedVideoSource = async source => { sources.push(source) }
  f.controller._forceMicOffForAwayEntry = () => { f.controller._micEnabled = false }
  for (const to of ["away", "live"]) {
    let prevented = false
    await f.controller.changeBoothStatus({ target: { action: `https://example.test/status?to=${to}` },
      preventDefault() { prevented = true }, stopImmediatePropagation() {} })
    assert.equal(prevented, true)
    assert.equal(f.controller._boothStatus, to)
    assert.equal(f.requests.at(-1).params.request_id, f.controller._publisherAttempt.requestId)
    assert.equal(f.requests.at(-1).params.stream_session_id, 7)
    assert.equal(f.requests.at(-1).params.generation, 1)
  }
  assert.deepEqual(sources, ["canvas", "processed"])
  assert.equal(f.controller._switchingVideoSource, false)
})

test("R03 a delayed status response from an old screen cannot switch replacement media", async () => {
  const response = deferred()
  const f = fixture({ statusResponse: response })
  const initial = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await initial
  let mediaChanges = 0
  f.controller._switchPublishedVideoSource = async () => { mediaChanges++ }
  const changing = f.controller.changeBoothStatus({ target: { action: "https://example.test/status?to=away" },
    preventDefault() {}, stopImmediatePropagation() {} })
  await until(() => f.requests.at(-1).path === "/status")
  const previous = f.controller._publisherAttempt
  previous.invalidate()
  f.controller._publisherAttempt = { newScreen: true }
  f.controller._stage = { newStage: true }
  f.controller._boothStatus = "live"
  response.resolve()
  await changing
  assert.equal(mediaChanges, 0)
  assert.equal(f.controller._boothStatus, "live")
})

test("R02 terminal SDK leave during confirmation preserves the saved result but requires resume", async () => {
  const confirmResponse = deferred()
  const f = fixture({ confirmResponse })
  const starting = f.controller.startBroadcast()
  await until(() => f.stages.length === 1)
  f.stages[0].publish()
  await until(() => f.confirms === 1)
  f.stages[0].emit("left")
  confirmResponse.resolve()
  await starting
  assert.equal(f.controller._broadcasting, false)
  assert.equal(f.controller._resumable, true)
  assert.equal(f.controller._stage, null)
  assert.equal(f.controller._publisherRecoveryPending, false)
  assert.equal(f.requests.filter(r => r.path === "/cancel").length, 0)
})

for (const rollbackFails of [false, true]) {
  test(`R01 media switch failure ${rollbackFails ? "requires resume when state recovery fails" : "restores the previous server state"}`, async () => {
    const f = fixture({ statusFailureOn: rollbackFails ? 2 : 0 })
    const initial = f.controller.startBroadcast()
    await until(() => f.stages.length === 1)
    f.stages[0].publish()
    await initial
    f.controller._switchPublishedVideoSource = async source => {
      if (source === "canvas") throw new Error("canvas unavailable")
    }
    await f.controller.changeBoothStatus({ target: { action: "https://example.test/status?to=away" },
      preventDefault() {}, stopImmediatePropagation() {} })
    assert.deepEqual(f.requests.filter(r => r.path === "/status").map(r => r.params.to), ["away", "live"])
    if (rollbackFails) {
      assert.equal(f.controller._stage, null)
      assert.equal(f.controller._broadcasting, false)
      assert.equal(f.controller._resumable, true)
    } else {
      assert.equal(f.controller._boothStatus, "live")
      assert.equal(f.controller._broadcasting, true)
      assert.equal(f.controller._switchingVideoSource, false)
    }
  })
}

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
