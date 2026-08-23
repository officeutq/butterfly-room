const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/lp_analytics_form_controller.js"
)

function loadController({ trackable = true, visitId = "visit-uuid" } = {}) {
  const sends = []
  let senderCount = 0
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source.replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}"
  )
  source = source.replace(
    /import \{[\s\S]*?\} from "lp_analytics\/event_sender"/,
    "const { EventSender, isTrackableDocument, storedVisitId, viewportType } = globalThis.LpAnalyticsTestDependencies"
  )
  source = source.replace(
    "export default class extends Controller",
    "globalThis.LpAnalyticsFormController = class extends Controller"
  )

  class FakeEventSender {
    constructor(options) {
      this.options = options
      senderCount += 1
    }

    send(...args) {
      sends.push({ options: this.options, args })
      return Promise.resolve(true)
    }
  }

  const document = {
    createElement(tagName) {
      return { tagName: tagName.toUpperCase(), type: "", name: "", value: "" }
    },
  }
  const context = vm.createContext({
    console,
    document,
    LpAnalyticsTestDependencies: {
      EventSender: FakeEventSender,
      isTrackableDocument: () => trackable,
      storedVisitId: () => visitId,
      viewportType: () => "smartphone",
    },
  })
  vm.runInContext(source, context, { filename: controllerPath })

  return {
    Controller: context.LpAnalyticsFormController,
    sends,
    senderCount: () => senderCount,
  }
}

function buildForm() {
  const children = []
  return {
    tagName: "FORM",
    children,
    querySelector(selector) {
      if (selector !== 'input[name="lp_analytics_visit_id"]') return null
      return children.find((child) => child.name === "lp_analytics_visit_id") || null
    },
    appendChild(child) {
      children.push(child)
    },
  }
}

test("LP経由formの実表示を同一tabの訪問IDへ送信する", () => {
  const environment = loadController()
  const form = buildForm()
  const controller = Object.assign(new environment.Controller(), {
    element: form,
    hasEventsUrlValue: true,
    eventsUrlValue: "/lp_analytics/events",
    hasEventTypeValue: true,
    eventTypeValue: "store_registration_form_view",
    hasLpIdentifierValue: true,
    lpIdentifierValue: "stores_lp_202609",
  })

  controller.connect()

  assert.equal(environment.senderCount(), 1)
  assert.deepEqual(JSON.parse(JSON.stringify(environment.sends)), [
    {
      options: {
        eventsUrl: "/lp_analytics/events",
        visitId: "visit-uuid",
        lpIdentifier: "stores_lp_202609",
      },
      args: ["store_registration_form_view", null, { viewport_type: "smartphone" }],
    },
  ])
  assert.equal(form.children.length, 1)
  assert.equal(form.children[0].type, "hidden")
  assert.equal(form.children[0].name, "lp_analytics_visit_id")
  assert.equal(form.children[0].value, "visit-uuid")
})

test("Turbo previewではform表示イベントもhidden訪問IDも追加しない", () => {
  const environment = loadController({ trackable: false })
  const form = buildForm()
  const controller = Object.assign(new environment.Controller(), {
    element: form,
    hasEventsUrlValue: true,
    eventsUrlValue: "/lp_analytics/events",
    hasEventTypeValue: true,
    eventTypeValue: "store_contact_form_view",
    hasLpIdentifierValue: true,
    lpIdentifierValue: "stores_lp_202609",
  })

  controller.connect()

  assert.equal(environment.senderCount(), 0)
  assert.equal(environment.sends.length, 0)
  assert.equal(form.children.length, 0)
})
