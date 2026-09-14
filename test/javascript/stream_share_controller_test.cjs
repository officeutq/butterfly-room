const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers/stream_share_controller.js"), "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
  .replace('export default class extends Controller', 'globalThis.StreamShare = class extends Controller')

function setup() {
  const requests = []
  const timers = new Set()
  const window = { setTimeout(fn) { timers.add(fn); return fn }, clearTimeout(fn) { timers.delete(fn) } }
  const context = vm.createContext({ window, AbortController,
    fetch(url, options) { return new Promise((resolve, reject) => requests.push({ url, options, resolve, reject })) } })
  vm.runInContext(source, context)
  const controller = new context.StreamShare()
  controller.urlValue = "/cast/stream_sessions/100/share"
  let html = "old preparation X"
  controller.contentTarget = {
    get innerHTML() { return html }, set innerHTML(value) { html = value },
    get textContent() { return html }, set textContent(value) { html = value }
  }
  controller.errorTarget = { hidden: true }
  return { controller, requests, timers }
}

function response(html, status = 200, redirected = false) {
  return { ok: status >= 200 && status < 300, redirected, text: async () => html }
}

test("共有を開くたびに指定した配信の最新情報を取得し応答前に古い共有先を除く", async () => {
  const { controller, requests, timers } = setup()
  const first = controller.refresh()
  assert.equal(controller.contentTarget.textContent, "共有情報を取得しています…")
  assert.equal(requests[0].url, "/cast/stream_sessions/100/share")
  assert.equal(requests[0].options.credentials, "same-origin")
  requests[0].resolve(response("配信未開始"))
  await first
  assert.equal(controller.contentTarget.innerHTML, "配信未開始")
  const second = controller.refresh()
  requests[1].resolve(response("Publisher Y X/LINE/WebShare"))
  await second
  assert.equal(controller.contentTarget.innerHTML, "Publisher Y X/LINE/WebShare")
  assert.equal(timers.size, 0)
})

test("取得失敗やログインへの転送では古い人物を共有せず再確認で回復する", async () => {
  for (const failed of [response("error", 503), response("login", 200, true)]) {
    const { controller, requests } = setup()
    const first = controller.refresh()
    requests[0].resolve(failed)
    await first
    assert.equal(controller.contentTarget.textContent, "")
    assert.equal(controller.errorTarget.hidden, false)
    const retry = controller.refresh()
    requests[1].resolve(response("Y"))
    await retry
    assert.equal(controller.contentTarget.innerHTML, "Y")
    assert.equal(controller.errorTarget.hidden, true)
  }
})

test("閉じた画面の遅い応答は再度開いた共有内容を上書きしない", async () => {
  const { controller, requests } = setup()
  const first = controller.refresh()
  controller.cancel()
  assert.equal(requests[0].options.signal.aborted, true)
  const second = controller.refresh()
  requests[1].resolve(response("Y"))
  await second
  requests[0].resolve(response("X"))
  await first
  assert.equal(controller.contentTarget.innerHTML, "Y")
  const third = controller.refresh()
  controller.disconnect()
  requests[2].reject(new Error("disconnected"))
  await third
  assert.equal(controller.errorTarget.hidden, true)
})

test("通信期限を過ぎた取得は中断して再確認を表示する", async () => {
  const { controller, requests, timers } = setup()
  const pending = controller.refresh()
  const timeout = [...timers][0]
  timeout()
  assert.equal(requests[0].options.signal.aborted, true)
  requests[0].reject(new Error("aborted"))
  await pending
  assert.equal(controller.errorTarget.hidden, false)
  assert.equal(controller.contentTarget.textContent, "")
  assert.equal(timers.size, 0)
})
