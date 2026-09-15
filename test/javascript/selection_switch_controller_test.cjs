const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function setup({ confirm = true, response = { ok: true, json: async () => ({ redirect_url: "/cast/booths/2" }) } } = {}) {
  const calls = [], visits = [], confirmations = [], forms = []
  const buttons = [{ disabled: false }, { disabled: true }]
  const element = { contains: () => false, querySelectorAll: () => buttons, setAttribute() {} }
  let source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers/selection_switch_controller.js"), "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace("export default class extends Controller", "globalThis.SelectionSwitchController = class extends Controller")
  const document = { forms, querySelector: () => ({ content: "csrf" }), querySelectorAll: () => [] }
  const context = vm.createContext({
    document, FormData: class { constructor(form) { this.form = form } },
    fetch: async (...args) => { calls.push(args); if (response instanceof Error) throw response; return response },
    window: { confirm: message => { confirmations.push(message); return confirm }, Turbo: { cache: { clear() {} }, visit: url => visits.push(url) } },
  })
  vm.runInContext(source, context)
  const controller = Object.assign(new context.SelectionSwitchController(), { element, errorTarget: { hidden: true } })
  const submit = () => controller.submit({ preventDefault() {}, target: { action: "/cast/current_booth" } })
  const form = { method: "post", dataset: {}, elements: [], closest: () => null }
  forms.push(form)
  return { controller, calls, visits, confirmations, form, buttons, submit, document, window: context.window }
}

test("dirty cancellation does not send selection or discard input", async () => {
  const s = setup({ confirm: false })
  s.form.dataset.dirty = "true"
  await s.submit()
  assert.equal(s.calls.length, 0)
  assert.equal(s.visits.length, 0)
  assert.equal(s.form.dataset.dirty, "true")
  assert.equal(s.buttons[0].disabled, false)
})

test("confirmed selection posts once and visits the server's new target", async () => {
  const s = setup()
  s.form.dataset.dirty = "true"
  await s.submit()
  await s.submit()
  assert.equal(s.calls.length, 1)
  assert.equal(s.confirmations.length, 1)
  assert.equal(s.calls[0][1].headers.Accept, "application/json")
  assert.deepEqual(s.visits, ["/cast/booths/2"])
})

for (const response of [{ ok: false, json: async () => ({ message: "配信を終了してから切り替えてください" }) }, new Error("network unavailable")]) {
  test(`selection error preserves original form and permits retry: ${response.ok ?? "network"}`, async () => {
    const s = setup({ response })
    s.form.dataset.dirty = "true"
    await s.submit()
    assert.equal(s.visits.length, 0)
    assert.equal(s.controller.errorTarget.hidden, false)
    assert.equal(s.form.dataset.dirty, "true")
    assert.equal(s.buttons[0].disabled, false)
    assert.equal(s.buttons[1].disabled, true)
    await s.submit()
    assert.equal(s.calls.length, 2)
  })
}

test("existing form dirty state includes image edits and overrides stale default values after saving", () => {
  const s = setup()
  s.form.elements = [{ name: "name", type: "text", value: "saved", defaultValue: "old" }]
  s.form.dataset.dirty = "false"
  assert.equal(s.controller.hasUnsavedChanges(), false)
  s.form.dataset.dirty = "true"
  assert.equal(s.controller.hasUnsavedChanges(), true)
})

test("plain drink and account forms detect text, checks, files and selections", () => {
  const s = setup()
  for (const field of [
    { type: "text", value: "new", defaultValue: "old" },
    { type: "checkbox", checked: true, defaultChecked: false },
    { type: "file", files: [{}] },
    { type: "select-one", options: [{ selected: false, defaultSelected: true }, { selected: true, defaultSelected: false }] },
  ]) {
    s.form.elements = [{ name: "field", ...field }]
    assert.equal(s.controller.hasUnsavedChanges(), true, field.type)
  }
  s.form.elements = [{ name: "field", type: "select-one", options: [{ selected: true, defaultSelected: false }, { selected: false, defaultSelected: false }] }]
  assert.equal(s.controller.hasUnsavedChanges(), false)
  s.form.method = "get"
  s.form.elements = [{ name: "search", type: "text", value: "new", defaultValue: "" }]
  assert.equal(s.controller.hasUnsavedChanges(), false)
})

test("store selection for cast invitation continues inside the modal and updates header names", async () => {
  const s = setup({ response: { ok: true, json: async () => ({ redirect_url: "/admin/cast_invitations/new", frame: "modal", store_name: "店舗B", booth_name: null }) } })
  const modal = {}, names = { store: { classList: { toggle() {} } }, booth: { classList: { toggle() {} } } }
  s.document.getElementById = () => modal
  s.document.querySelectorAll = selector => [selector.includes("store") ? names.store : names.booth]
  await s.submit()
  assert.equal(modal.src, "/admin/cast_invitations/new")
  assert.equal(names.store.textContent, "店舗B")
  assert.equal(names.booth.textContent, "未選択")
  assert.equal(s.visits.length, 0)
})

test("selection waits for cancellation of the publisher start before POST", async () => {
  const s = setup()
  let release
  const pending = new Promise(resolve => { release = resolve })
  const steps = []
  s.window.publisher = {
    async prepareSelectionSwitch() { steps.push("prepare"); await pending },
    async completeSelectionSwitch() { steps.push("dispose") },
  }
  const submit = s.submit()
  assert.equal(s.calls.length, 0)
  release()
  await submit
  assert.deepEqual(steps, ["prepare", "dispose"])
  assert.equal(s.calls.length, 1)
})

test("unresolved publisher cancellation blocks selection and restores the original UI", async () => {
  const s = setup()
  let resumes = 0
  s.window.publisher = {
    async prepareSelectionSwitch() { throw new Error("配信接続の確認待ちです") },
    resumeAfterSelectionFailure() { resumes++ },
  }
  await s.submit()
  assert.equal(s.calls.length, 0)
  assert.equal(resumes, 1)
  assert.equal(s.controller.errorTarget.hidden, false)
})

test("a media disposal error after committed selection still leaves the old preparation screen", async () => {
  const s = setup()
  s.window.publisher = { async prepareSelectionSwitch() {}, async completeSelectionSwitch() { throw new Error("media") } }
  await s.submit()
  assert.deepEqual(s.visits, ["/cast/booths/2"])
})
