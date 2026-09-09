const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const test = require("node:test")

function setup(navigator = {}) {
  const events = []
  const source = fs.readFileSync("app/javascript/controllers/cast_invitation_controller.js", "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace('import { Modal } from "bootstrap"', "")
    .replace("export default class extends Controller", "globalThis.Invite = class extends Controller")
  let hidden = 0
  const context = vm.createContext({ navigator, document: {}, window: { dispatchEvent: e => events.push(e) },
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail } },
    Modal: { getInstance: () => ({ hide: () => hidden++ }) } })
  vm.runInContext(source, context)
  const c = new context.Invite()
  for (const name of ["error", "status", "retry", "content", "url", "expires", "note", "unsupported", "cancelHelp", "shareButton", "closeLabel"]) c[`${name}Target`] = { value: "", hidden: false }
  c.closeButtonTargets = [{}]
  c.element = {}
  c.invitation = { url: "https://example.test/invite", text: "店舗の管理者から", update_url: "/invite/1", shared_url: "/invite/1/shared" }
  c.savedNote = ""
  c.completed = false
  c.useCopy = !navigator.share
  c.request = async () => ({ step: "go_dashboard_for_drinks", store_id: 1 })
  return { c, events, hidden: () => hidden }
}

test("share starts before note persistence finishes, and successful share keeps modal open", async () => {
  const order = []
  const { c, hidden } = setup({ share: async () => { order.push("share") } })
  c.noteTarget.value = "管理メモ"
  c.request = async (_url, method) => { order.push(method); return {} }
  await c.share()
  assert.equal(order[0], "share")
  assert.equal(c.savedNote, "管理メモ")
  assert.equal(c.completed, true)
  assert.equal(c.closeLabelTarget.textContent, "閉じる")
  assert.equal(hidden(), 0)
})

test("share cancellation keeps saved memo and invitation cancellable", async () => {
  const { c } = setup({ share: async () => { throw Object.assign(new Error(), { name: "AbortError" }) } })
  c.noteTarget.value = "入力済み"
  const calls = []
  c.request = async (_url, method) => { calls.push(method); return {} }
  await c.share()
  assert.equal(c.savedNote, "入力済み")
  assert.equal(c.completed, false)
  assert.deepEqual(calls, ["PATCH"])
})

test("unsupported share copies only URL", async () => {
  let copied
  const { c } = setup({ clipboard: { writeText: async text => { copied = text } } })
  await c.share()
  assert.equal(copied, c.invitation.url)
  assert.equal(c.completed, true)
})

test("successful sharing and failed note save preserve completion and retry on close", async () => {
  const { c, hidden } = setup({ share: async () => {} })
  c.noteTarget.value = "残すメモ"
  let fail = true
  c.request = async (_url, method) => { if (method === "PATCH" && fail) throw new Error("保存失敗"); return {} }
  await c.share()
  assert.equal(c.completed, true)
  assert.equal(c.errorTarget.hidden, false)
  await c.close()
  assert.equal(hidden(), 0)
  fail = false
  await c.close()
  assert.equal(c.savedNote, "残すメモ")
  assert.equal(hidden(), 1)
})

test("cancel failure keeps modal open and retry succeeds", async () => {
  const { c, hidden } = setup()
  c.request = async () => { throw new Error("取消失敗") }
  await c.close()
  assert.equal(hidden(), 0)
  c.request = async (_url, method) => { assert.equal(method, "DELETE"); return {} }
  await c.close()
  assert.equal(hidden(), 1)
})

test("failed shared notification retries on close without invoking share again", async () => {
  let shares = 0
  const { c, hidden } = setup({ share: async () => { shares++ } })
  c.request = async () => { throw new Error("通信失敗") }
  await c.share()
  assert.equal(c.completed, true)
  c.request = async () => ({})
  await c.close()
  assert.equal(shares, 1)
  assert.equal(hidden(), 1)
})

test("failed share offers copy without marking completion", async () => {
  const { c } = setup({ share: async () => { throw new Error("共有失敗") } })
  await c.share()
  assert.equal(c.useCopy, true)
  assert.equal(c.completed, false)
  assert.equal(c.shareButtonTarget.textContent, "招待URLをコピー")
})

test("busy operation ignores repeated share and close", async () => {
  const { c, hidden } = setup({ share: () => { throw new Error("must not run") } })
  c.busy = true
  await c.share()
  await c.close()
  assert.equal(hidden(), 0)
})
