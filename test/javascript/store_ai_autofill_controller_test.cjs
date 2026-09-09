const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const filename = path.resolve(__dirname, "../../app/javascript/controllers/store_ai_autofill_controller.js")
const fieldNames = ["description", "area", "business_type", "address", "phone_number", "business_hours",
  "website_url", "x_url", "instagram_url", "tiktok_url", "youtube_url"]

class Node {
  constructor() {
    this.children = []
    this.hidden = false
    this.value = ""
    this.textContent = ""
    this.attributes = {}
    this.classList = { add() {} }
  }
  append(...items) { this.children.push(...items) }
  replaceChildren(...items) { this.children = items }
  setAttribute(name, value) { this.attributes[name] = value }
  focus() { this.focused = true }
  remove() { this.removed = true }
}

function setup() {
  const timers = new Map()
  const requests = []
  let request = async () => { throw new Error("network") }
  const context = vm.createContext({
    AbortController, Event, URL, File, Blob,
    document: { createElement: () => new Node(), querySelector: () => ({ content: "csrf" }) },
    window: {
      setTimeout(callback) { timers.set(callback, callback); return callback },
      clearTimeout(id) { timers.delete(id) }
    },
    fetch(...args) { requests.push(args); return request(...args) }
  })
  const source = fs.readFileSync(filename, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace("export default class extends Controller", "globalThis.SetupController = class extends Controller")
  vm.runInContext(source, context, { filename })
  const controller = new context.SetupController()
  const inputs = Object.fromEntries(fieldNames.map((field) => {
    const input = new Node()
    input.id = `store_${field}`
    input.labels = [{ textContent: field }]
    input.closest = () => ({ parentElement: new Node() })
    input.dispatchEvent = () => controller.edited({ target: input })
    return [field, input]
  }))
  controller.element = new Node()
  controller.element.querySelector = (selector) => inputs[/store\[([^\]]+)\]/.exec(selector)?.[1]] || null
  context.SetupController.targets.forEach((target) => { controller[`${target}Target`] = new Node() })
  controller.nameTarget.value = "確認した店舗名"
  controller.detailsTarget.hidden = true
  controller.detailsTarget.disabled = true
  controller.initialValue = true
  controller.searchLabelTargets = []
  controller.readyValue = false
  controller.urlValue = "/admin/stores/1/ai_autofill"
  controller.timeoutValue = 50000
  controller.connect()
  return { controller, inputs, requests, timers, respond: (fn) => { request = fn } }
}

function result(values = {}) {
  return {
    status: "partial",
    fields: Object.fromEntries(fieldNames.map((field) => [field, values[field] ?? null])),
    field_sources: { area: ["https://example.com/store"] },
    sources: [{ url: "https://example.com/store", title: "店舗公式" }]
  }
}

function response(data, status = 200) {
  return { ok: status === 200, status, json: async () => data }
}

test("optional image request remains locked and its timeout preserves the completed text result", async () => {
  const env = setup()
  env.controller.hasImageUrlValue = true
  env.controller.imageUrlValue = "/admin/stores/1/ai_autofill/image"
  let imports = 0
  env.controller.imageEditor = () => ({ canImportCandidate: () => true, importCandidate: async () => { imports++ } })
  let imageStarted
  const started = new Promise((resolve) => { imageStarted = resolve })
  env.respond((url, options) => {
    if (url === env.controller.urlValue) return Promise.resolve(response({ ...result({ area: "保持する" }), image_token: "signed" }))
    return new Promise((_, reject) => {
      options.signal.addEventListener("abort", () => reject(new Error("timeout")))
      imageStarted()
    })
  })
  const pending = env.controller.search()
  await started
  assert.equal(env.controller.contentTarget.inert, true)
  assert.equal(env.inputs.area.value, "保持する")
  await env.controller.search()
  assert.equal(env.requests.length, 2)
  Array.from(env.timers.values())[0]()
  await pending
  assert.equal(env.controller.busy, false)
  assert.equal(env.controller.readyValue, true)
  assert.equal(env.controller.fields.get("area").origin, "ai")
  assert.equal(env.inputs.area.value, "保持する")
  assert.match(env.controller.resultMessageTarget.textContent, /AIで見つかった/)
  assert.equal(imports, 0)
  assert.equal(env.timers.size, 0)
})

function submitEvent() {
  return { prevented: false, stopped: false,
    preventDefault() { this.prevented = true }, stopImmediatePropagation() { this.stopped = true } }
}

function regularSetup() {
  const env = setup()
  env.controller.initialValue = false
  for (const target of ["intro", "initialAction", "reviewHeader", "reviewHeading", "details"]) {
    delete env.controller[`${target}Target`]
  }
  env.controller.searchLabelTargets = [new Node()]
  return env
}

test("regular editing preserves loaded fields without badges and needs no initial-step targets", async () => {
  const env = regularSetup()
  env.inputs.business_hours.value = "保存済み営業時間"
  env.inputs.description.value = "以前AIで保存した概要"
  env.respond(async () => response(result({ area: "空欄へ入力", business_hours: "上書き不可", description: "上書き不可" })))
  const event = submitEvent()
  env.controller.guardSubmit(event)
  assert.equal(event.prevented, false)
  await env.controller.search()
  assert.equal(env.inputs.business_hours.value, "保存済み営業時間")
  assert.equal(env.inputs.description.value, "以前AIで保存した概要")
  assert.equal(env.controller.fields.get("business_hours").origin, null)
  assert.equal(env.inputs.area.value, "空欄へ入力")
  assert.equal(env.controller.fields.get("area").origin, "ai")
  assert.equal(env.controller.searchLabelTargets[0].textContent, "AIで再検索")
  assert.equal(env.controller.resultMessageTarget.focused, true)
  assert.equal(env.requests.length, 1)
})

test("a search that changes only badge state reports no value changes", async () => {
  const env = regularSetup()
  env.respond(async () => response(result()))
  await env.controller.search()
  assert.match(env.controller.resultMessageTarget.textContent, /入力内容に変更はありませんでした/)
  assert.equal(env.controller.fields.get("area").origin, "missing")
  assert.equal(env.controller.applyResult(result()), 0)
  assert.equal(env.controller.applyResult(result({ area: "変更あり" })), 1)
})

test("protected text does not skip image import or claim text was inserted", async () => {
  const env = regularSetup()
  Object.values(env.inputs).forEach((input) => { input.value = "保存済み" })
  env.controller.hasImageUrlValue = true
  env.controller.imageUrlValue = "/admin/stores/1/ai_autofill/image"
  let imports = 0
  env.controller.imageEditor = () => ({ canImportCandidate: () => true, importCandidate: async () => { imports++; return true } })
  env.respond(async (url) => url === env.controller.urlValue
    ? response({ ...result({ area: "上書き不可" }), image_token: "signed" })
    : { ok: true, status: 200, blob: async () => new Blob(["image"], { type: "image/jpeg" }),
      headers: { get: () => "https://example.com/image-source" } })
  await env.controller.search()
  assert.equal(env.requests.length, 2)
  assert.equal(imports, 1)
  assert.equal(env.inputs.area.value, "保存済み")
  assert.match(env.controller.resultMessageTarget.textContent, /店舗画像を入力しました/)
  assert.equal(env.controller.sourcesTarget.children.length, 1)
})

test("image permission errors keep text and release the form with an actionable message", async () => {
  const env = regularSetup()
  env.controller.hasImageUrlValue = true
  env.controller.imageUrlValue = "/admin/stores/1/ai_autofill/image"
  env.controller.imageEditor = () => ({ canImportCandidate: () => true })
  env.respond(async (url) => url === env.controller.urlValue
    ? response({ ...result({ area: "検索結果" }), image_token: "signed" }) : response({}, 403))
  await env.controller.search()
  assert.equal(env.inputs.area.value, "検索結果")
  assert.equal(env.controller.fields.get("area").origin, "ai")
  assert.equal(env.controller.contentTarget.inert, false)
  assert.match(env.controller.resultMessageTarget.textContent, /管理権限/)
})

test("AI application badges values and missing fields without treating it as user editing", () => {
  const { controller, inputs } = setup()
  controller.applyResult(result({ area: "渋谷", description: "紹介文" }))
  assert.equal(inputs.area.value, "渋谷")
  assert.equal(controller.fields.get("area").origin, "ai")
  assert.equal(controller.fields.get("address").origin, "missing")
  assert.equal(inputs.address.value, "")
  assert.equal(controller.nameTarget.value, "確認した店舗名")
  assert.equal(controller.fields.has("name"), false)
  assert.equal(controller.fields.has("thumbnail"), false)
  assert.equal(controller.sourcesTarget.children.length, 1)
})

test("manual values survive re-search; cleared inputs become eligible without resurrecting badges on edit", () => {
  const { controller, inputs } = setup()
  controller.applyResult(result({ area: "渋谷", description: "古いAI紹介" }))
  inputs.area.value = "利用者が修正"
  controller.edited({ target: inputs.area })
  assert.equal(controller.fields.get("area").badge.hidden, true)
  controller.applyResult(result({ area: "上書き不可", phone_number: "123" }))
  assert.equal(inputs.area.value, "利用者が修正")
  assert.equal(controller.fields.get("area").origin, null)
  assert.equal(inputs.description.value, "")
  assert.equal(controller.fields.get("description").origin, "missing")
  // The original source of a protected value remains available.
  assert.equal(controller.sourcesTarget.children.length, 1)
  inputs.area.value = ""
  controller.edited({ target: inputs.area })
  assert.equal(controller.fields.get("area").origin, null)
  controller.applyResult(result({ area: "再入力" }))
  assert.equal(inputs.area.value, "再入力")
  assert.equal(controller.fields.get("area").origin, "ai")
})

test("one request locks editing and submission, then reveals the review without another request", async () => {
  const env = setup()
  let finish
  env.respond(() => new Promise((resolve) => { finish = resolve }))
  const first = env.controller.search()
  await env.controller.search()
  assert.equal(env.requests.length, 1)
  assert.equal(env.controller.contentTarget.inert, true)
  const event = submitEvent()
  env.controller.guardSubmit(event)
  assert.equal(event.stopped, true)
  assert.deepEqual(JSON.parse(env.requests[0][1].body), { store_ai_autofill: { store_name: "確認した店舗名" } })
  finish(response(result({ area: "渋谷" })))
  await first
  assert.equal(env.controller.contentTarget.inert, false)
  assert.equal(env.controller.detailsTarget.hidden, false)
  assert.equal(env.controller.detailsTarget.disabled, false)
  assert.equal(env.controller.readyValue, true)
  assert.equal(env.timers.size, 0)
  assert.equal(env.requests.length, 1)
})

test("empty and overlong names do not search or reveal the form; initial submit is blocked", async () => {
  const { controller, requests } = setup()
  for (const name of ["   ", "店".repeat(256)]) {
    controller.nameTarget.value = name
    await controller.search()
    assert.equal(controller.nameErrorTarget.hidden, false)
    assert.equal(controller.readyValue, false)
  }
  assert.equal(requests.length, 0)
  const event = submitEvent()
  controller.guardSubmit(event)
  assert.equal(event.prevented, true)
})

for (const [status, message] of [["not_found", "店舗情報が見つかりませんでした"], ["ambiguous", "店舗を特定できませんでした"], ["error", "AI入力を利用できませんでした"]]) {
  test(`${status} reveals manual editing and preserves existing values, badges and sources`, async () => {
    const { controller, inputs, respond } = setup()
    controller.applyResult(result({ area: "保持する" }))
    respond(async () => response({ status }, status === "error" ? 429 : 200))
    await controller.search()
    assert.equal(controller.detailsTarget.hidden, false)
    assert.equal(inputs.area.value, "保持する")
    assert.equal(controller.fields.get("area").origin, "ai")
    assert.equal(controller.sourcesTarget.children.length, 1)
    assert.ok(controller.resultMessageTarget.textContent.includes(message))

    const fresh = setup()
    fresh.respond(async () => response({ status }, status === "error" ? 503 : 200))
    await fresh.controller.search()
    assert.ok(Array.from(fresh.controller.fields.values()).every((entry) => entry.origin === null))
  })
}

test("timeout allows manual editing; late completion after disconnect cannot modify the form", async () => {
  const env = setup()
  env.respond((_, options) => new Promise((_, reject) => {
    options.signal.addEventListener("abort", () => reject(new Error("timeout")))
  }))
  const pending = env.controller.search()
  Array.from(env.timers.values())[0]()
  await pending
  assert.equal(env.controller.readyValue, true)
  assert.equal(env.controller.busy, false)

  let finish
  env.respond(() => new Promise((resolve) => { finish = resolve }))
  const late = env.controller.search()
  env.controller.disconnect()
  finish(response(result({ area: "遅れた結果" })))
  await late
  assert.equal(env.inputs.area.value, "")
})

test("authentication and malformed responses preserve inputs instead of masquerading as missing data", async () => {
  const env = setup()
  env.controller.applyResult(result({ area: "保持する" }))
  env.respond(async () => response({}, 403))
  await env.controller.search()
  assert.match(env.controller.resultMessageTarget.textContent, /管理権限/)
  env.respond(async () => response({ status: "success", fields: {} }))
  await env.controller.search()
  assert.equal(env.inputs.area.value, "保持する")
  assert.equal(env.controller.fields.get("area").origin, "ai")
})

test("saving and failed save retain fields, origins and sources without searching again", () => {
  const { controller, inputs, requests } = setup()
  controller.applyResult(result({ area: "渋谷" }))
  controller.showReview("partial")
  inputs.description.value = "手入力"
  controller.edited({ target: inputs.description })
  controller.saving()
  assert.equal(controller.contentTarget.inert, true)
  controller.saveFailed()
  assert.equal(controller.contentTarget.inert, false)
  assert.equal(controller.detailsTarget.hidden, false)
  assert.equal(controller.fields.get("area").origin, "ai")
  assert.equal(controller.fields.get("description").origin, null)
  assert.equal(inputs.description.value, "手入力")
  assert.equal(controller.sourcesTarget.children.length, 1)
  assert.equal(requests.length, 0)
})

test("busy state blocks page navigation and restores only regions it locked", () => {
  const { controller } = setup()
  const header = new Node()
  const alreadyInert = new Node()
  alreadyInert.inert = true
  const body = new Node()
  body.children = [header, controller.element, alreadyInert]
  controller.element.parentElement = body
  controller.setBusy(true, "検索中")
  assert.equal(header.inert, true)
  assert.equal(controller.contentTarget.inert, true)
  controller.setBusy(false)
  assert.equal(header.inert, false)
  assert.equal(alreadyInert.inert, true)
  controller.setBusy(true, "検索中")
  controller.disconnect()
  assert.equal(controller.contentTarget.inert, false)
  assert.equal(header.inert, false)
  assert.equal(alreadyInert.inert, true)
})

test("source links use only safe URLs and text nodes", () => {
  const { controller } = setup()
  const data = result({ area: "渋谷" })
  data.sources[0].title = "<script>unsafe()</script>"
  data.sources.push({ url: "javascript:unsafe()", title: "bad" })
  data.field_sources.area.push("javascript:unsafe()")
  controller.applyResult(data)
  const link = controller.sourcesTarget.children[0].children[0]
  assert.equal(controller.sourcesTarget.children.length, 1)
  assert.equal(link.textContent, "<script>unsafe()</script>")
  assert.equal(link.rel, "noopener noreferrer")
})
