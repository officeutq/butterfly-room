const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function loadController(filename, globals = {}) {
  const source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers", filename), "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace("export default class extends Controller", "globalThis.ModalController = class extends Controller")
  const context = vm.createContext({ ...globals })
  vm.runInContext(source, context)
  return context.ModalController
}

test("pending request blocks closing and navigation, then allows retry after a network error", () => {
  const Controller = loadController("account_modal_form_controller.js")
  const buttons = [{ disabled: false }, { disabled: false }]
  const attributes = new Map()
  const controller = Object.assign(new Controller(), {
    element: {
      querySelectorAll: () => buttons,
      setAttribute: (name, value) => attributes.set(name, value),
      removeAttribute: name => attributes.delete(name),
    },
    errorTarget: { hidden: true },
  })
  controller.start()
  assert.ok(buttons.every(button => button.disabled))
  assert.equal(attributes.get("aria-busy"), "true")
  let blocked = 0
  const event = { preventDefault() { blocked++ }, target: { closest: () => ({}) } }
  controller.beforeClose(event)
  controller.beforeNavigate(event)
  assert.equal(blocked, 2)
  controller.failed(event)
  assert.equal(controller.errorTarget.hidden, false)
  assert.match(controller.errorTarget.textContent, /通信に失敗/)
  assert.ok(buttons.every(button => !button.disabled))
  assert.equal(attributes.has("aria-busy"), false)
  controller.beforeClose(event)
  assert.equal(blocked, 3)
  controller.start()
  assert.equal(controller.errorTarget.hidden, true)
  controller.finish()
  assert.equal(controller.sending, false)
})

test("completion clears stale cache and releases pending state before closing without navigating", () => {
  const calls = []
  const Controller = loadController("account_modal_complete_controller.js", {
    window: { Turbo: { cache: { clear: () => calls.push("clear-cache") } } },
  })
  const form = {}
  const frame = { querySelector: () => form }
  const controller = Object.assign(new Controller(), {
    element: { closest: () => frame },
    application: {
      getControllerForElementAndIdentifier(element, identifier) {
        if (identifier === "account-modal-form") {
          assert.equal(element, form)
          return { finish: () => calls.push("finish") }
        }
        assert.equal(element, frame)
        return { close: () => calls.push("close") }
      },
    },
  })
  controller.connect()
  assert.deepEqual(calls, ["clear-cache", "finish", "close"])
})
