const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/profile_edit_controller.js"
)

function loadController({ confirmResult = true } = {}) {
  const listeners = new Map()
  const confirmations = []
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace(
      "export default class extends Controller",
      "globalThis.ProfileEditController = class extends Controller"
    )

  const context = vm.createContext({
    JSON,
    Array,
    queueMicrotask,
    window: {
      addEventListener(name, callback) { listeners.set(name, callback) },
      removeEventListener(name) { listeners.delete(name) },
      confirm(message) {
        confirmations.push(message)
        return confirmResult
      },
    },
  })
  vm.runInContext(source, context, { filename: controllerPath })
  return { Controller: context.ProfileEditController, confirmations, listeners }
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
  const operationInputs = [{ value: "" }, { value: "" }]
  const saveButton = { disabled: false }
  const backLink = {
    attributes: {},
    classList: classList(),
    setAttribute(name, value) { this.attributes[name] = value },
  }
  const element = {
    attributes: {},
    dataset: {},
    querySelectorAll() { return operationInputs },
    setAttribute(name, value) { this.attributes[name] = value },
    removeAttribute(name) { delete this.attributes[name] },
  }
  const controller = Object.assign(new Controller(), {
    element,
    displayNameTarget: { value: "現在の名前" },
    bioTarget: { value: "現在の自己紹介" },
    saveButtonTarget: saveButton,
    backLinkTarget: backLink,
  })
  controller.connect()
  return { backLink, controller, element, operationInputs, saveButton }
}

test("starts clean and enables save after a field changes", () => {
  const { Controller } = loadController()
  const { controller, element, saveButton } = buildController(Controller)

  assert.equal(element.dataset.dirty, "false")
  assert.equal(saveButton.disabled, true)

  controller.displayNameTarget.value = "変更後の名前"
  controller.refresh()

  assert.equal(element.dataset.dirty, "true")
  assert.equal(saveButton.disabled, false)
})

test("tracks staged and reverted image operations", () => {
  const { Controller } = loadController()
  const { controller, operationInputs, saveButton } = buildController(Controller)

  operationInputs[0].value = "replace"
  controller.refresh()
  assert.equal(saveButton.disabled, false)

  operationInputs[0].value = ""
  controller.refresh()
  assert.equal(saveButton.disabled, true)
})

test("keeps the user on the page when discarding changes is rejected", () => {
  const { Controller, confirmations } = loadController({ confirmResult: false })
  const { controller } = buildController(Controller)
  controller.bioTarget.value = "変更後"
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
  const { backLink, controller, element, saveButton } = buildController(Controller)
  controller.bioTarget.value = "変更後"
  controller.refresh()
  const event = { defaultPrevented: false, imageAttachmentEditorInvalid: false }

  controller.prepareSubmit(event)
  await new Promise((resolve) => setImmediate(resolve))

  assert.equal(saveButton.disabled, true)
  assert.equal(element.attributes["aria-busy"], "true")
  assert.equal(backLink.classList.contains("disabled"), true)
  assert.equal(backLink.attributes["aria-disabled"], "true")
})
