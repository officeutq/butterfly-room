const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/booth_form_controller.js"
)

function loadController({ confirmResult = true } = {}) {
  const confirmations = []
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace(
      "export default class extends Controller",
      "globalThis.BoothFormController = class extends Controller"
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
  return { Controller: context.BoothFormController, confirmations }
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

function buildController(Controller, { initialDirty = false } = {}) {
  const submitButtons = [
    { name: "commit", type: "submit", value: "保存", disabled: true, dataset: { submittingLabel: "保存中…" } },
    { name: "commit", type: "submit", value: "保存", disabled: true, dataset: { submittingLabel: "保存中…" } },
  ]
  const controls = [
    { name: "authenticity_token", type: "hidden", value: "token", disabled: false },
    { name: "booth[name]", type: "text", value: "現在のブース名", disabled: false },
    { name: "booth_cast[cast_user_id]", type: "select-one", value: "", disabled: false },
    { name: "booth[description]", type: "textarea", value: "現在の説明", disabled: false },
    { name: "image_pair[operation]", type: "hidden", value: "", disabled: false },
    { name: "image_pair[source]", type: "file", value: "", disabled: false },
    ...submitButtons,
  ]
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
    submitButtonTargets: submitButtons,
    backLinkTarget: backLink,
    initialDirtyValue: initialDirty,
  })
  controller.connect()
  return { backLink, controller, controls, element, submitButtons }
}

test("starts clean and enables submit after any booth field changes", () => {
  const { Controller } = loadController()
  const { controller, controls, element, submitButtons } = buildController(Controller)

  assert.equal(element.dataset.dirty, "false")
  assert.equal(submitButtons.every((button) => button.disabled), true)

  controls[1].value = "変更後のブース名"
  controller.refresh()

  assert.equal(element.dataset.dirty, "true")
  assert.equal(submitButtons.every((button) => !button.disabled), true)
})

test("tracks image operations and cast assignment", () => {
  const { Controller } = loadController()
  const { controller, controls, submitButtons } = buildController(Controller)

  controls[4].value = "replace"
  controller.refresh()
  assert.equal(submitButtons.every((button) => !button.disabled), true)

  controls[4].value = ""
  controller.refresh()
  assert.equal(submitButtons.every((button) => button.disabled), true)

  controls[2].value = "42"
  controller.refresh()
  assert.equal(submitButtons.every((button) => !button.disabled), true)
})

test("keeps a server-rejected creation retryable on reconnect", () => {
  const { Controller } = loadController()
  const { controller, element, submitButtons } = buildController(Controller, { initialDirty: true })

  assert.equal(element.dataset.dirty, "true")
  assert.equal(controller.dirty, true)
  assert.equal(submitButtons.every((button) => !button.disabled), true)
})

test("keeps the user on the page when discarding changes is rejected", () => {
  const { Controller, confirmations } = loadController({ confirmResult: false })
  const { controller, controls } = buildController(Controller)
  controls[3].value = "変更後の説明"
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
  const { backLink, controller, controls, element, submitButtons } = buildController(Controller)
  controls[1].value = "変更後のブース名"
  controller.refresh()

  controller.prepareSubmit({ defaultPrevented: false, imageAttachmentEditorInvalid: false })
  await new Promise((resolve) => setImmediate(resolve))

  assert.equal(submitButtons.every((button) => button.disabled), true)
  assert.deepEqual(submitButtons.map((button) => button.value), ["保存中…", "保存中…"])
  assert.equal(element.attributes["aria-busy"], "true")
  assert.equal(backLink.classList.contains("disabled"), true)
  assert.equal(backLink.attributes["aria-disabled"], "true")
})
