const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function setup() {
  const events = [], details = []
  const source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers/selection_lock_controller.js"), "utf8")
    .replace(/^import .*$/gm, "")
    .replace("export default class extends Controller", "globalThis.SelectionLockController = class extends Controller")
  const context = vm.createContext({
    Controller: class {}, CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options?.detail } },
    window: { dispatchEvent: event => { events.push(event.type); details.push(event.detail) } },
  })
  vm.runInContext(source, context)
  const header = new context.SelectionLockController()
  const storeName = { textContent: "店舗A", classList: { remove() {} } }, boothName = { textContent: "ブースA", classList: { remove() {} } }
  header.element = { querySelectorAll: selector => [selector.includes("store") ? storeName : boothName] }
  const unrelatedLink = { href: "/dashboard" }
  const children = [storeName, boothName].map(name => ({
    href: "/select_modal", childNodes: [name],
    replaceWith(...nodes) { children.splice(children.indexOf(this), 1, ...nodes) },
  }))
  children.push(unrelatedLink)
  Object.defineProperty(header, "linkTargets", { get: () => children.filter(child => child.href === "/select_modal") })
  return { header, children, storeName, boothName, unrelatedLink, events, details, Controller: context.SelectionLockController }
}

test("broadcast lock removes both selection links while preserving names and unrelated navigation", () => {
  const s = setup()
  s.header.connect()
  assert.equal(s.header.linkTargets.length, 2)
  assert.deepEqual(s.events, [])
  s.header.lock()
  assert.equal(s.header.linkTargets.length, 0)
  assert.deepEqual(s.children, [s.storeName, s.boothName, s.unrelatedLink])
  s.header.lock()
  assert.deepEqual(s.children, [s.storeName, s.boothName, s.unrelatedLink])
})

test("server rejection of a stale selection opener notifies the header without navigation", () => {
  const s = setup()
  const notice = new s.Controller()
  notice.lockedValue = true
  notice.storeNameValue = "店舗B"
  notice.boothNameValue = "ブースB"
  notice.connect()
  assert.deepEqual(s.events, ["selection:locked"])
  s.header.lock({ detail: s.details[0] })
  assert.equal(s.storeName.textContent, "店舗B")
  assert.equal(s.boothName.textContent, "ブースB")
  assert.equal(s.header.linkTargets.length, 0)
})
