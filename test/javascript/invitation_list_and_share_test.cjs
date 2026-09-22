const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const test = require("node:test")

function controller(file, globals = {}) {
  const source = fs.readFileSync(`app/javascript/controllers/${file}_controller.js`, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace("export default class extends Controller", "globalThis.Subject = class extends Controller")
  const context = vm.createContext({ AbortController, window: { setTimeout, clearTimeout }, ...globals })
  vm.runInContext(source, context)
  return new context.Subject()
}

test("list refresh waits for closing and ignores a different store", async () => {
  let reads = 0, replaced = 0, cleared = 0
  const c = controller("invitation_list", { fetch: async () => { reads++; return { ok: true, text: async () => "response" } },
    DOMParser: class { parseFromString() { return { querySelector: () => ({ childNodes: ["new list"] }) } } },
    window: { setTimeout, clearTimeout, Turbo: { cache: { clear: () => cleared++ } } } })
  c.storeIdValue = 5
  c.urlValue = "/admin/casts?tab=admin_invitations&selection_store_id=5"
  c.contentTarget = { replaceChildren: (...nodes) => { assert.deepEqual(nodes, ["new list"]); replaced++ } }
  c.errorTarget = { hidden: true }
  c.changed({ detail: { storeId: 6 } })
  await c.refresh()
  assert.equal(reads, 0)
  c.changed({ detail: { storeId: 5 } })
  assert.equal(reads, 0)
  await c.refresh()
  assert.equal(replaced, 1)
  assert.equal(cleared, 1)
  await c.refresh()
  assert.equal(reads, 1)
})

test("changed selection and network failure keep the displayed list and show recovery guidance", async () => {
  for (const fail of [async () => ({ ok: false }), async () => { throw Error("network") }]) {
    const c = controller("invitation_list", { fetch: fail })
    c.needsRefresh = true
    c.element = { isConnected: true }
    c.errorTarget = { hidden: true }
    c.contentTarget = { replaceChildren: () => assert.fail("must keep existing list") }
    await c.refresh()
    assert.equal(c.errorTarget.hidden, false)
    assert.match(c.errorTarget.textContent, /選択店舗/)
    assert.equal(c.needsRefresh, true)
  }
})

test("failed clipboard fallback never signals successful sharing", async () => {
  let signalled = false
  const c = controller("clipboard", { navigator: {}, document: {
    createElement: () => ({ setAttribute() {}, style: {}, select() {} }),
    body: { appendChild() {}, removeChild() {} }, execCommand: () => false
  }, window: { setTimeout: callback => callback() } })
  c.element = { dataset: { clipboardText: "https://example.test/invite" } }
  c.dispatch = () => { signalled = true }
  const flashes = []
  c.showFlash = (level, message) => flashes.push({ level, message })
  await c.copy({ preventDefault() {} })
  assert.equal(signalled, false)
  assert.equal(flashes[0].level, "danger")
})
