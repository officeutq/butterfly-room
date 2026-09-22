const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const test = require("node:test")

function setup(navigator = {}, admin = false) {
  const events = []
  const source = fs.readFileSync("app/javascript/controllers/invitation_modal_controller.js", "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace('import { Modal } from "bootstrap"', "")
    .replace("export default class extends Controller", "globalThis.Invite = class extends Controller")
  let hidden = 0
  const context = vm.createContext({ navigator, document: {}, window: { dispatchEvent: e => events.push(e) },
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options?.detail } },
    Modal: { getInstance: () => ({ hide: () => hidden++ }) } })
  vm.runInContext(source, context)
  const c = new context.Invite()
  for (const name of ["error", "status", "retry", "content", "url", "expires", "note", "unsupported", "cancelHelp", "shareButton", "closeLabel"]) c[`${name}Target`] = { value: "", hidden: false }
  c.closeButtonTargets = [{}]
  c.element = { dataset: {} }
  c.invitation = { url: "https://example.test/invite", text: "店舗の管理者から", update_url: "/invite/1", shared_url: "/invite/1/shared" }
  c.savedNote = ""
  c.adminValue = admin
  c.storeIdValue = 1
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

test("share text includes the URL once for destinations that only receive text", async () => {
  let payload
  const { c } = setup({ share: async value => { payload = value } })
  await c.share()
  assert.equal(payload.text, `${c.invitation.text}\n\n${c.invitation.url}`)
  assert.equal(payload.url, undefined)
  assert.equal(c.element.dataset.onboardingInvitationState, "close")
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

test("manager invitation uses its own memo payload and never updates cast onboarding", async () => {
  const { c, events, hidden } = setup({ clipboard: { writeText: async () => {} } }, true)
  c.noteTarget.value = "管理者への招待メモ"
  const requests = []
  c.request = async (url, method, body) => { requests.push({ url, method, body }); return { step: "go_dashboard_for_drinks", store_id: 1 } }
  await c.share()
  assert.equal(requests[0].body.store_admin_invitation.note, "管理者への招待メモ")
  assert.equal(requests[0].body.store_cast_invitation, undefined)
  assert.equal(c.element.dataset.onboardingInvitationState, undefined)
  assert.equal(events.length, 0)
  assert.equal(hidden(), 0)
  c.noteTarget.value = "閉じる前の修正"
  await c.close()
  assert.equal(c.savedNote, "閉じる前の修正")
  assert.equal(hidden(), 1)
  assert.equal(events[0].type, "invitation:changed")
  assert.equal(events[0].detail.storeId, 1)
})

test("manager share success with failed note and completion storage is retried without cancelling", async () => {
  let shares = 0
  const { c, hidden } = setup({ share: async () => { shares++ } }, true)
  c.noteTarget.value = "保持するメモ"
  c.request = async () => { throw new Error("通信失敗") }
  await c.share()
  assert.equal(c.completed, true)
  await c.close()
  assert.equal(hidden(), 0)
  const methods = []
  c.request = async (_url, method) => { methods.push(method); return {} }
  await c.close()
  assert.deepEqual(methods, ["PATCH", "POST"])
  assert.equal(shares, 1)
  assert.equal(hidden(), 1)
})

test("unknown issue response is recovered with the original request key before cancellation", async () => {
  const { c, hidden } = setup({}, true)
  c.invitation = null
  c.createUrlValue = "/admin/store_admin_invitations"
  c.requestKeyValue = "same-request-key"
  const requests = []
  let fail = true
  c.request = async (url, method, body) => {
    requests.push({ url, method, body })
    if (fail) throw new Error("応答が失われました")
    return { url: "https://example.test/invite", update_url: "/invitation/1", note: "", shared: false }
  }
  await c.issue()
  assert.equal(c.invitation, null)
  fail = false
  await c.close()
  assert.equal(requests[0].body.request_key, requests[1].body.request_key)
  assert.equal(requests[2].method, "DELETE")
  assert.equal(hidden(), 1)
})
