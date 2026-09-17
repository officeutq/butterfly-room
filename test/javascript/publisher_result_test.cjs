const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function load(name, globals) {
  const context = vm.createContext({ Controller: class {}, ...globals })
  const source = fs.readFileSync(path.resolve(__dirname, `../../app/javascript/controllers/${name}_controller.js`), "utf8")
    .replace(/^import .*$/gm, "").replace("export default class extends Controller", "globalThis.Loaded = class extends Controller")
  vm.runInContext(source, context)
  return new context.Loaded()
}

test("forced-end notification stops only the matching session and immediately visits its result", () => {
  for (const sessionId of [7, 8]) {
    const events = []
    const publisher = { streamSessionIdValue: 7, _publisherEndRequest: {}, _broadcasting: true,
      _publisherAttempt: { invalidate: () => events.push("invalidate") }, _cleanupStage: () => events.push("leave"),
      _cleanupMediaAndCanvas: async () => events.push("stop-media") }
    const controller = load("publisher_ended", { window: { Turbo: { visit: url => events.push(url) } } })
    Object.assign(controller, { sessionIdValue: sessionId, urlValue: "/result/7",
      element: { closest: () => ({}) }, application: { getControllerForElementAndIdentifier: () => publisher } })
    controller.connect()
    assert.deepEqual(events, sessionId === 7 ? ["invalidate", "leave", "stop-media", "/result/7"] : [])
    assert.equal(publisher._broadcasting, sessionId !== 7)
  }
})

function resultFixture(fetchResult) {
  const timers = new Map(), requests = [], classes = new Set()
  let sequence = 0
  const controller = load("publisher_disconnect_status", {
    AbortController,
    setTimeout(callback, delay) { const id = ++sequence; timers.set(id, { callback, delay }); return id },
    clearTimeout(id) { timers.delete(id) },
    fetch: async (url, options) => { requests.push({ url, options }); return fetchResult(requests.length) },
  })
  Object.assign(controller, { urlValue: "/result-state", stateValue: "retrying",
    element: { textContent: "", classList: { toggle: (name, on) => on ? classes.add(name) : classes.delete(name) } } })
  return { controller, requests, timers, classes }
}

const settle = () => new Promise(resolve => setImmediate(resolve))

test("result read is bounded and never calls a mutation even if notifications do not arrive", async () => {
  const f = resultFixture(async () => ({ ok: true, json: async () => ({ disconnect_state: "retrying", message: "再試行中" }) }))
  f.controller.connect()
  const delays = []
  for (let i = 0; i < 4; i++) {
    await settle()
    const entry = [...f.timers.entries()].find(([, timer]) => timer.delay < 15000)
    if (!entry) break
    f.timers.delete(entry[0]); delays.push(entry[1].delay); entry[1].callback()
  }
  await settle()
  assert.equal(f.requests.length, 4)
  assert.deepEqual(delays, [500, 1000, 2000])
  assert.ok(f.requests.every(r => !r.options.method && !r.options.body))
  assert.match(f.controller.element.textContent, /画面を読み込み直して/)
  assert.equal(f.timers.size, 0)
})

test("terminal failure is shown and a delayed read from a disconnected view cannot replace it", async () => {
  let resolveOld
  const old = new Promise(resolve => { resolveOld = resolve })
  const f = resultFixture(async count => count === 1 ? old : ({ ok: true, json: async () => ({ disconnect_state: "failed", message: "切断失敗" }) }))
  f.controller.connect()
  f.controller.disconnect()
  f.controller.connect()
  await settle()
  assert.equal(f.controller.element.textContent, "切断失敗")
  assert.ok(f.classes.has("alert-danger"))
  resolveOld({ ok: true, json: async () => ({ disconnect_state: "retrying", message: "古い結果" }) })
  await settle()
  assert.equal(f.controller.element.textContent, "切断失敗")
  assert.equal(f.requests.length, 2)
  assert.equal(f.timers.size, 0)
})
