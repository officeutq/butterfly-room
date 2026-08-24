const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/store_ai_autofill_controller.js"
)

class FakeNode {
  constructor(tagName = "div") {
    this.tagName = tagName
    this.children = []
    this.hidden = false
    this.textContent = ""
    this.attributes = {}
    this.listeners = new Map()
  }

  append(...children) {
    this.children.push(...children)
  }

  replaceChildren(...children) {
    this.children = [...children]
  }

  setAttribute(name, value) {
    this.attributes[name] = value
  }

  addEventListener(name, callback) {
    this.listeners.set(name, callback)
  }

  dispatchEvent(event) {
    this.listeners.get(event.type)?.(event)
  }
}

function loadController() {
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source.replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}"
  )
  source = source.replace(
    'import { Modal } from "bootstrap"',
    "class Modal {}"
  )
  source = source.replace(
    "export default class extends Controller",
    "globalThis.StoreAiAutofillController = class extends Controller"
  )

  const listeners = new Map()
  const timers = new Map()
  const fetchCalls = []
  let nextTimerId = 1
  let fetchImplementation = () => Promise.reject(new Error("fetch is not configured"))

  const document = {
    body: new FakeNode("body"),
    addEventListener(name, callback) {
      listeners.set(name, callback)
    },
    removeEventListener(name) {
      listeners.delete(name)
    },
    createElement(tagName) {
      return new FakeNode(tagName)
    },
    createTextNode(text) {
      const node = new FakeNode("text")
      node.textContent = text
      return node
    },
    querySelector() {
      return null
    }
  }

  const window = {
    location: { origin: "https://example.test" },
    setTimeout(callback, delay) {
      const id = nextTimerId++
      timers.set(id, { callback, delay })
      return id
    },
    clearTimeout(id) {
      timers.delete(id)
    }
  }

  const context = vm.createContext({
    AbortController,
    Error,
    Event,
    Map,
    Object,
    Promise,
    String,
    URL,
    document,
    window,
    fetch(...args) {
      fetchCalls.push(args)
      return fetchImplementation(...args)
    }
  })
  vm.runInContext(source, context, { filename: controllerPath })

  return {
    Controller: context.StoreAiAutofillController,
    document,
    fetchCalls,
    listeners,
    timers,
    setFetchImplementation(callback) {
      fetchImplementation = callback
    }
  }
}

function buildController(Controller, overrides = {}) {
  return Object.assign(
    new Controller(),
    {
      snapshot: {},
      visibleCandidates: new Map(),
      candidatesTarget: new FakeNode(),
      sourcesTarget: new FakeNode(),
      sourcesSectionTarget: new FakeNode(),
      sourcesCountTarget: new FakeNode(),
      titleTarget: new FakeNode(),
      bodyTarget: new FakeNode(),
      loadingTarget: new FakeNode(),
      messageTarget: new FakeNode(),
      errorCodeTarget: new FakeNode(),
      headerCloseButtonTarget: new FakeNode("button"),
      closeButtonTarget: new FakeNode("button"),
      applyButtonTarget: new FakeNode("button"),
      searchButtonTarget: new FakeNode("button"),
      hasSearchButtonTarget: true,
      timeoutValue: 50000,
      urlValue: "/admin/stores/1/ai_autofill"
    },
    overrides
  )
}

function emptyFields() {
  return {
    description: null,
    area: null,
    business_type: null,
    address: null,
    phone_number: null,
    business_hours: null,
    website_url: null,
    x_url: null,
    instagram_url: null,
    tiktok_url: null,
    youtube_url: null
  }
}

test("normalizes common strings, phone numbers, and URLs only for comparison", () => {
  const { Controller } = loadController()
  const controller = buildController(Controller)

  assert.equal(controller.valuesEqual("area", " ＡＢＣ\r\n", "ABC"), true)
  assert.equal(controller.valuesEqual("phone_number", "03-1234-5678", "0312345678"), true)
  assert.equal(
    controller.valuesEqual(
      "website_url",
      "https://Example.com:443/store/#section",
      "https://example.com/store"
    ),
    true
  )
  assert.equal(controller.valuesEqual("business_type", "snack", "lounge"), false)
})

test("checks new values by default and leaves replacements unchecked", () => {
  const { Controller } = loadController()
  const controller = buildController(Controller)

  controller.snapshot = { area: "" }
  assert.equal(controller.buildCandidateRow("area", "渋谷区", []).checkbox.checked, true)

  controller.snapshot = { area: "新宿区" }
  assert.equal(controller.buildCandidateRow("area", "渋谷区", []).checkbox.checked, false)
})

test("groups additions and replacements separately", () => {
  const { Controller } = loadController()
  const controller = buildController(Controller, {
    snapshot: { area: "", phone_number: "03-0000-0000" }
  })
  controller.renderSources = () => {}
  controller.renderState = () => {}

  controller.renderResponse({
    status: "partial",
    fields: {
      ...emptyFields(),
      area: "福岡市博多区",
      phone_number: "092-000-0000"
    },
    sources: []
  })

  assert.equal(controller.candidatesTarget.children.length, 2)
  assert.equal(controller.candidatesTarget.children[0].children[0].children[0].textContent, "新しく追加される情報")
  assert.equal(controller.candidatesTarget.children[1].children[0].children[0].textContent, "既存情報の変更候補")
})

test("updates the apply button with the selected candidate count", () => {
  const { Controller } = loadController()
  const controller = buildController(Controller)
  controller.visibleCandidates = new Map([
    ["area", { checkbox: { checked: true } }],
    ["address", { checkbox: { checked: true } }],
    ["phone_number", { checkbox: { checked: false } }]
  ])

  controller.updateApplyButton()

  assert.equal(controller.applyButtonTarget.disabled, false)
  assert.equal(controller.applyButtonTarget.textContent, "2項目を反映")

  controller.visibleCandidates.forEach((candidate) => { candidate.checkbox.checked = false })
  controller.updateApplyButton()

  assert.equal(controller.applyButtonTarget.disabled, true)
  assert.equal(controller.applyButtonTarget.textContent, "項目を選択してください")
})

test("shows unique sources in one collapsed section", () => {
  const { Controller } = loadController()
  const controller = buildController(Controller)
  controller.sourcesSectionTarget.open = true

  controller.renderSources([
    { title: "店舗公式", url: "https://example.com/store" },
    { title: "重複", url: "https://example.com/store" },
    { title: "公式SNS", url: "https://x.com/example" },
    { title: "不正", url: "javascript:alert(1)" }
  ])

  assert.equal(controller.sourcesTarget.children.length, 2)
  assert.equal(controller.sourcesCountTarget.textContent, "2件")
  assert.equal(controller.sourcesSectionTarget.hidden, false)
  assert.equal(controller.sourcesSectionTarget.open, false)
})

test("shows only changed allowlisted candidates and uses no_changes when none remain", () => {
  const { Controller } = loadController()
  const states = []
  const controller = buildController(Controller, {
    snapshot: { area: "", phone_number: "03-1234-5678" }
  })
  controller.buildCandidateRow = (field, value) => ({
    element: { field },
    checkbox: { checked: value !== "" }
  })
  controller.renderSources = () => {}
  controller.renderState = (state) => states.push(state)

  controller.renderResponse({
    status: "partial",
    fields: {
      ...emptyFields(),
      area: "渋谷区",
      phone_number: "0312345678",
      published: "true"
    },
    field_sources: {},
    sources: []
  })

  assert.deepEqual(Array.from(controller.visibleCandidates.keys()), ["area"])
  assert.equal(states.pop(), "partial")

  controller.snapshot = { area: "渋谷区" }
  controller.renderResponse({
    status: "partial",
    fields: { ...emptyFields(), area: "渋谷区" },
    field_sources: {},
    sources: []
  })
  assert.equal(states.pop(), "no_changes")
})

test("applies only checked allowlisted fields without submitting the form", () => {
  const { Controller } = loadController()
  const events = []
  const fields = {
    description: {
      value: "現在の概要",
      dispatchEvent(event) { events.push(["description", event.type]) }
    },
    area: {
      value: "現在の地域",
      dispatchEvent(event) { events.push(["area", event.type]) }
    }
  }
  let hideCount = 0
  const controller = buildController(Controller, {
    modal: { hide() { hideCount += 1 } }
  })
  controller.element = {
    querySelector(selector) {
      const match = selector.match(/^\[name="store\[(.+)\]"\]$/)
      return match ? fields[match[1]] || null : null
    }
  }
  controller.visibleCandidates = new Map([
    ["description", { value: "AI概要", checkbox: { checked: true } }],
    ["area", { value: "渋谷区", checkbox: { checked: false } }],
    ["published", { value: "true", checkbox: { checked: true } }]
  ])

  controller.apply()

  assert.equal(fields.description.value, "AI概要")
  assert.equal(fields.area.value, "現在の地域")
  assert.deepEqual(events, [["description", "input"], ["description", "change"]])
  assert.equal(hideCount, 1)
})

test("opens immediately and blocks a second request while a search is in flight", async () => {
  const environment = loadController()
  let resolveFetch
  environment.setFetchImplementation(() => new Promise((resolve) => { resolveFetch = resolve }))
  let showCount = 0
  let loadingCount = 0
  let responseCount = 0
  const controller = buildController(environment.Controller, {
    requestInFlight: false,
    isConnected: true,
    abortController: null,
    timeoutId: null
  })
  controller.captureSnapshot = () => ({})
  controller.renderLoading = () => { loadingCount += 1 }
  controller.modalInstance = () => ({ show() { showCount += 1 } })
  controller.requestHeaders = () => ({ Accept: "application/json" })
  controller.readJson = async (response) => response.payload
  controller.renderResponse = () => { responseCount += 1 }

  const firstRequest = controller.search()
  await controller.search()

  assert.equal(showCount, 1)
  assert.equal(loadingCount, 1)
  assert.equal(environment.fetchCalls.length, 1)
  assert.equal(controller.searchButtonTarget.disabled, true)

  resolveFetch({ ok: true, payload: { status: "partial" } })
  await firstRequest

  assert.equal(responseCount, 1)
  assert.equal(controller.requestInFlight, false)
  assert.equal(controller.searchButtonTarget.disabled, false)
})

test("shows a safe server error code with the generic error message", async () => {
  const environment = loadController()
  environment.setFetchImplementation(async () => ({
    ok: false,
    payload: { status: "error", error_code: "openai_rate_limited" }
  }))
  const controller = buildController(environment.Controller, {
    requestInFlight: false,
    isConnected: true,
    abortController: null,
    timeoutId: null
  })
  controller.captureSnapshot = () => ({})
  controller.renderLoading = () => {}
  controller.modalInstance = () => ({ show() {} })
  controller.requestHeaders = () => ({ Accept: "application/json" })
  controller.readJson = async (response) => response.payload

  await controller.search()

  assert.equal(controller.titleTarget.textContent, "検索を完了できませんでした")
  assert.equal(controller.messageTarget.textContent, "時間をおいて、もう一度お試しください。")
  assert.equal(controller.errorCodeTarget.hidden, false)
  assert.equal(controller.errorCodeTarget.textContent, "エラーコード：openai_rate_limited")
})

test("uses unknown_error when an error code is missing or unsupported", () => {
  const { Controller } = loadController()
  const controller = buildController(Controller)

  controller.renderState("error", "unexpected error details")

  assert.equal(controller.errorCodeTarget.textContent, "エラーコード：unknown_error")
})

test("cleanup aborts the request and disposes the modal", () => {
  const { Controller } = loadController()
  let abortCount = 0
  let disposeCount = 0
  const controller = buildController(Controller, {
    requestInFlight: true,
    timeoutId: 99,
    abortController: { abort() { abortCount += 1 } },
    modal: { dispose() { disposeCount += 1 } }
  })

  controller.cleanup()

  assert.equal(abortCount, 1)
  assert.equal(disposeCount, 1)
  assert.equal(controller.requestInFlight, false)
  assert.equal(controller.searchButtonTarget.disabled, false)
})
