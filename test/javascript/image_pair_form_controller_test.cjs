const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/image_pair_form_controller.js"
)

function loadController({ response = { redirect_url: "/dashboard" }, error = null } = {}) {
  const requests = []
  const navigations = []
  const clients = []
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace(
      'import { ImagePairMultipartClient } from "image_attachments/multipart_client"',
      "const ImagePairMultipartClient = globalThis.FakeClient"
    )
    .replace(
      "export default class extends Controller",
      "globalThis.ImagePairFormController = class extends Controller"
    )

  class FakeClient {
    constructor() {
      this.aborted = false
      clients.push(this)
    }

    submit(request) {
      requests.push(request)
      return error ? Promise.reject(error) : Promise.resolve(response)
    }

    abort() {
      this.aborted = true
    }
  }

  class FakeFormData {
    constructor(form) {
      this.form = form
    }
  }

  const context = vm.createContext({
    FakeClient,
    FormData: FakeFormData,
    Promise,
    URL,
    queueMicrotask,
    window: {
      location: {
        origin: "https://example.test",
        assign(value) { navigations.push(value) },
      },
    },
  })
  vm.runInContext(source, context, { filename: controllerPath })
  return { Controller: context.ImagePairFormController, clients, navigations, requests }
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

function buildEditor(operation) {
  const status = { textContent: "", classList: classList() }
  const editor = {
    querySelector(selector) {
      return selector.includes("status") ? status : null
    },
  }
  return {
    editor,
    input: {
      value: operation,
      closest() { return editor },
    },
    status,
  }
}

function buildController(Controller, operations) {
  const editors = operations.map(buildEditor)
  const form = {
    action: "https://example.test/profile",
    method: "post",
    attributes: {},
    querySelectorAll() { return editors.map((entry) => entry.input) },
    setAttribute(name, value) { this.attributes[name] = value },
    removeAttribute(name) { delete this.attributes[name] },
  }
  const button = { disabled: false }
  const errorTarget = {
    hidden: true,
    textContent: "",
    focused: false,
    focus() { this.focused = true },
  }
  const controller = Object.assign(new Controller(), {
    element: form,
    errorTarget,
    hasErrorTarget: true,
    submitButtonTargets: [button],
  })
  controller.connect()
  return { button, controller, editors, errorTarget, form }
}

function submitEvent() {
  return {
    prevented: false,
    preventDefault() { this.prevented = true },
  }
}

function flushPromises() {
  return new Promise((resolve) => setImmediate(resolve))
}

test("leaves a normal profile update to Turbo when no image operation exists", async () => {
  const environment = loadController()
  const { controller } = buildController(environment.Controller, ["", ""])
  const event = submitEvent()

  controller.submit(event)
  await flushPromises()

  assert.equal(event.prevented, false)
  assert.equal(environment.requests.length, 0)
})

test("sends both image sections once and shows the saving state", async () => {
  const environment = loadController()
  const { button, controller, editors, errorTarget, form } = buildController(
    environment.Controller,
    ["replace", "reedit"]
  )
  const event = submitEvent()

  controller.submit(event)
  await flushPromises()

  assert.equal(event.prevented, true)
  assert.equal(environment.requests.length, 1)
  assert.equal(environment.requests[0].url, form.action)
  assert.equal(environment.requests[0].method, "POST")
  assert.equal(environment.requests[0].body.form, form)
  assert.equal(button.disabled, true)
  assert.equal(form.attributes["aria-busy"], "true")
  assert.equal(errorTarget.hidden, true)
  assert.match(editors[0].status.textContent, /保存しています/)
  assert.match(editors[1].status.textContent, /保存しています/)
  assert.deepEqual(environment.navigations, ["https://example.test/dashboard"])
})

test("does not send when an editor marks the submit event invalid", async () => {
  const environment = loadController()
  const { controller } = buildController(environment.Controller, ["replace", ""])
  const event = submitEvent()

  controller.submit(event)
  event.imageAttachmentEditorInvalid = true
  await flushPromises()

  assert.equal(event.prevented, true)
  assert.equal(environment.requests.length, 0)
})

test("keeps the prepared files for manual retry after a request error", async () => {
  const environment = loadController({ error: new Error("通信に失敗しました。再度保存してください。") })
  const { button, controller, editors, errorTarget } = buildController(
    environment.Controller,
    ["replace", ""]
  )

  controller.submit(submitEvent())
  await flushPromises()

  assert.equal(button.disabled, false)
  assert.equal(controller.element.attributes["aria-busy"], undefined)
  assert.equal(controller.submitting, false)
  assert.equal(errorTarget.hidden, false)
  assert.equal(errorTarget.focused, true)
  assert.match(errorTarget.textContent, /再度保存/)
  assert.equal(editors[0].status.classList.contains("text-danger"), true)
  assert.equal(editors[1].status.textContent, "")
})

test("aborts an active request when the form disconnects", () => {
  const environment = loadController()
  const { controller } = buildController(environment.Controller, ["replace"])
  const client = environment.clients[0]

  controller.disconnect()

  assert.equal(client.aborted, true)
  assert.equal(controller.client, null)
})
