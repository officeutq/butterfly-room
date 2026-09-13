const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const read = name => fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers", name), "utf8")
const controllerSource = read("ivs_publisher_controller.js").replace(/^import .*$/gm, "")
  .replace("export default class extends Controller", "globalThis.Publisher = class extends Controller")
const mediaSource = read("ivs_publisher/media_state.js").replace(/^import .*$/gm, "").replace(/export /g, "")

function deferred() {
  let resolve
  const promise = new Promise(r => { resolve = r })
  return { promise, resolve }
}

function setup({ joinGate, confirmFails = false } = {}) {
  const calls = { tokens: 0, confirms: 0, cancels: 0, stages: [], cleanup: 0 }
  class Stage {
    constructor() { calls.stages.push(this); this.publishing = false; this.leaves = 0 }
    async join() { if (joinGate) await joinGate.promise; this.publishing = true }
    leave() { this.leaves += 1; this.publishing = false }
  }
  const context = vm.createContext({
    Controller: class {}, console, crypto: { randomUUID: () => "attempt-current" },
    window: { sessionStorage: { setItem() {}, removeItem() {} }, IVSBroadcastClient: { Stage, LocalStageStream: class {}, SubscribeType: { NONE: 0 } } },
    cancelPublish: async () => { calls.cancels += 1 },
  })
  vm.runInContext(mediaSource, context)
  vm.runInContext(controllerSource, context)
  const c = new context.Publisher()
  Object.assign(c, {
    _publishGeneration: 0, _state: "idle", _mode: "normal", _boothStatus: "standby",
    hasTokenUrlValue: true, providerValue: "test", _attemptStorageKey: "test", _publishAttemptId: null,
    _beautyProvider: { ensureInitialBeautyStateLoaded: async () => {}, start: async () => {}, ensurePublishTrack: async () => {}, videoTrack: {}, stageStream: {} },
    _ensureAudioTrack: async () => {}, _applyManualMicState() {}, _clearError() {}, _setError(message) { this.error = message }, _humanizeError: e => e.message,
    _fetchParticipantToken: async () => { calls.tokens += 1; return "token" },
    _patchBroadcastStartedAt: async () => { calls.confirms += 1; if (confirmFails) throw new Error("confirm failed") },
    _patchBoothStatus: async () => {}, _reloadMetaDisplay: async () => {}, _applyCurrentMode() {},
    _syncUI() {}, _syncEffectPanelUI() {}, _syncBeautyPanelUI() {}, closeEffectPanel() {}, closeBeautyPanel() {},
    _cleanupMediaAndCanvas: async () => { calls.cleanup += 1 },
  })
  return { c, calls }
}

test("参加完了が画面離脱より後でも同じStageを退出し開始確定しない", async () => {
  const gate = deferred()
  const { c, calls } = setup({ joinGate: gate })
  const start = c.startBroadcast()
  await new Promise(setImmediate)
  assert.equal(calls.stages.length, 1)
  const end = c.endBroadcast({ skipFinish: true })
  gate.resolve()
  await Promise.all([start, end])
  assert.equal(calls.stages[0].publishing, false)
  assert.ok(calls.stages[0].leaves >= 2)
  assert.equal(calls.confirms, 0)
  assert.equal(c._stage, null)
})

test("サーバー確定失敗時は映像を送信し続けず予約取消を要求する", async () => {
  const { c, calls } = setup({ confirmFails: true })
  await c.startBroadcast()
  assert.equal(calls.stages[0].publishing, false)
  assert.equal(calls.confirms, 1)
  assert.ok(calls.cancels > 0)
  assert.equal(c._broadcasting, false)
  assert.equal(c.error, "confirm failed")
})

test("開始ボタン連打で参加やトークンを重複作成しない", async () => {
  const gate = deferred()
  const { c, calls } = setup({ joinGate: gate })
  const a = c.startBroadcast()
  const b = c.startBroadcast()
  gate.resolve()
  await Promise.all([a, b])
  assert.equal(calls.tokens, 1)
  assert.equal(calls.stages.length, 1)
  assert.equal(calls.confirms, 1)
})

test("終了API失敗後も同じ開始要求IDで終了を再試行できる", async () => {
  const { c } = setup()
  c.finishUrlValue = "/finish"
  c._publishAttemptId = "original"
  c._postFinish = async () => { throw new Error("終了未確認") }
  await c.endBroadcast()
  assert.equal(c._finishFailed, true)
  assert.equal(c._publishAttemptId, "original")
  assert.equal(c.error, "終了未確認")
})

test("開始確認・状態変更・終了要求は同じ開始要求IDを送る", async () => {
  const requests = []
  const context = vm.createContext({
    URL, document: { querySelector: () => ({ content: "csrf" }) }, window: { location: { origin: "https://example.test" } }, console,
    fetch: async (url, options) => {
      requests.push({ url, options })
      return { ok: true, status: 200, json: async () => ({ redirect_url: "/result" }), text: async () => "" }
    },
  })
  vm.runInContext(read("ivs_publisher/api_client.js").replace(/export /g, ""), context)
  const ctx = { _publishAttemptId: "current-id", hasStartBroadcastUrlValue: true, startBroadcastUrlValue: "/confirm", statusUrlValue: "/status", finishUrlValue: "/finish" }
  await context.patchBroadcastStartedAt(ctx)
  await context.patchBoothStatus(ctx, "away")
  assert.equal(await context.postFinish(ctx), "/result")
  assert.equal(JSON.parse(requests[0].options.body).publish_attempt_id, "current-id")
  assert.equal(new URL(requests[1].url).searchParams.get("publish_attempt_id"), "current-id")
  assert.equal(JSON.parse(requests[2].options.body).publish_attempt_id, "current-id")
})
