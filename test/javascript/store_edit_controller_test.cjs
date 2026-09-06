const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/store_edit_controller.js"
)

function loadController({ confirmResult = true } = {}) {
  const confirmations = []
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace(
      "export default class extends Controller",
      "globalThis.StoreEditController = class extends Controller"
    )

  const context = vm.createContext({
    JSON,
    Array,
    queueMicrotask,
    window: {
      addEventListener() {},
      removeEventListener() {},
      confirm(message) {
        confirmations.push(message)
        return confirmResult
      },
    },
  })
  vm.runInContext(source, context, { filename: controllerPath })
  return { Controller: context.StoreEditController, confirmations }
}

function classList() {
  const values = new Set()
  return {
    toggle(name, enabled) {
      if (enabled) values.add(name)
      else values.delete(name)
    },
    contains(name) { return values.has(name) },
  }
}

function buildController(Controller) {
  const controls = [
    { name: "authenticity_token", type: "hidden", value: "token", disabled: false },
    { name: "store[name]", type: "text", value: "現在の店舗名", disabled: false },
    { name: "store[published]", type: "select-one", value: "true", disabled: false },
    { name: "store[sales_support_company]", type: "checkbox", value: "1", checked: false, disabled: false },
    { name: "image_pair[operation]", type: "hidden", value: "", disabled: false },
    { name: "image_pair[source]", type: "file", value: "", disabled: false },
    { name: "commit", type: "submit", value: "保存", disabled: true },
  ]
  const saveButton = controls.at(-1)
  const backLink = {
    attributes: {},
    classList: classList(),
    setAttribute(name, value) { this.attributes[name] = value },
  }
  const element = {
    attributes: {},
    dataset: {},
    elements: controls,
    setAttribute(name, value) { this.attributes[name] = value },
    removeAttribute(name) { delete this.attributes[name] },
  }
  const controller = Object.assign(new Controller(), {
    element,
    saveButtonTarget: saveButton,
    backLinkTarget: backLink,
  })
  controller.connect()
  return { backLink, controller, controls, element, saveButton }
}

test("starts clean and enables save after any store field changes", () => {
  const { Controller } = loadController()
  const { controller, controls, element, saveButton } = buildController(Controller)

  assert.equal(element.dataset.dirty, "false")
  assert.equal(saveButton.disabled, true)

  controls[1].value = "変更後の店舗名"
  controller.refresh()

  assert.equal(element.dataset.dirty, "true")
  assert.equal(saveButton.disabled, false)
})

test("tracks image operations and checkbox changes", () => {
  const { Controller } = loadController()
  const { controller, controls, saveButton } = buildController(Controller)

  controls[4].value = "replace"
  controller.refresh()
  assert.equal(saveButton.disabled, false)

  controls[4].value = ""
  controller.refresh()
  assert.equal(saveButton.disabled, true)

  controls[3].checked = true
  controller.refresh()
  assert.equal(saveButton.disabled, false)
})

test("keeps the user on the page when discarding changes is rejected", () => {
  const { Controller, confirmations } = loadController({ confirmResult: false })
  const { controller, controls } = buildController(Controller)
  controls[2].value = "false"
  controller.refresh()
  const event = {
    prevented: false,
    preventDefault() { this.prevented = true },
  }

  controller.back(event)

  assert.equal(event.prevented, true)
  assert.deepEqual(confirmations, ["保存していない変更を破棄しますか？"])
})

test("marks a normal form submission as saving", async () => {
  const { Controller } = loadController()
  const { backLink, controller, controls, element, saveButton } = buildController(Controller)
  controls[1].value = "変更後の店舗名"
  controller.refresh()

  controller.prepareSubmit({ defaultPrevented: false, imageAttachmentEditorInvalid: false })
  await new Promise((resolve) => setImmediate(resolve))

  assert.equal(saveButton.disabled, true)
  assert.equal(element.attributes["aria-busy"], "true")
  assert.equal(backLink.classList.contains("disabled"), true)
  assert.equal(backLink.attributes["aria-disabled"], "true")
})
