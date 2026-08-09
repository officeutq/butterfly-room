const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/store_lp_202607_controller.js"
)

function loadController({ trackable = true } = {}) {
  const rememberedVisits = []
  const senderInstances = []
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source.replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}"
  )
  source = source.replace(
    /import \{[\s\S]*?\} from "lp_analytics\/event_sender"/,
    "const { EventSender, isTrackableDocument, rememberVisitId, viewportType } = globalThis.LpAnalyticsTestDependencies"
  )
  source = source.replace(
    "export default class extends Controller",
    "globalThis.StoreLp202607Controller = class extends Controller"
  )

  class FakeEventSender {
    constructor(options) {
      this.options = options
      this.calls = []
      senderInstances.push(this)
    }

    send(...args) {
      this.calls.push(args)
      return Promise.resolve(true)
    }
  }

  const document = {
    documentElement: { clientHeight: 1000, scrollHeight: 4000, scrollTop: 0 },
    body: { scrollHeight: 4000, scrollTop: 0 },
  }
  const window = {
    innerHeight: 1000,
    scrollY: 0,
    sessionStorage: {
      values: new Map(),
      getItem(key) { return this.values.get(key) || null },
      setItem(key, value) { this.values.set(key, value) },
    },
    requestAnimationFrame(callback) {
      callback()
      return 1
    },
    cancelAnimationFrame() {},
  }
  const context = vm.createContext({
    console,
    document,
    window,
    Promise,
    Set,
    LpAnalyticsTestDependencies: {
      EventSender: FakeEventSender,
      isTrackableDocument: () => trackable,
      rememberVisitId: (visitId) => rememberedVisits.push(visitId),
      viewportType: () => "pc",
    },
  })
  vm.runInContext(source, context, { filename: controllerPath })

  return {
    Controller: context.StoreLp202607Controller,
    document,
    window,
    rememberedVisits,
    senderInstances,
  }
}

test("各scroll率を初回到達時だけ送信する", () => {
  const environment = loadController()
  const calls = []
  const controller = Object.assign(new environment.Controller(), {
    analyticsEnabled: true,
    trackedOnceEvents: new Set(),
    visitIdValue: "visit-uuid",
    sendAnalytics: (...args) => calls.push(args),
  })

  controller.trackScrollReached()
  controller.trackScrollReached()
  environment.window.scrollY = 3000
  controller.trackScrollReached()

  assert.deepEqual(calls, [
    ["scroll_reached", "25"],
    ["scroll_reached", "50"],
    ["scroll_reached", "75"],
    ["scroll_reached", "90"],
  ])
})

test("sectionとCTA位置到達を同じcontroller接続内で重複送信しない", () => {
  const environment = loadController()
  const calls = []
  const controller = Object.assign(new environment.Controller(), {
    analyticsEnabled: true,
    trackedOnceEvents: new Set(),
    visitIdValue: "visit-uuid",
    sendAnalytics: (...args) => calls.push(args),
  })
  const section = {
    dataset: {
      lpAnalyticsReachType: "section_reached",
      lpAnalyticsEventValue: "PRICING",
    },
  }
  const cta = {
    dataset: {
      lpAnalyticsReachType: "cta_reached",
      lpAnalyticsEventValue: "bottom_registration",
    },
  }

  controller.trackReachTarget(section)
  controller.trackReachTarget(section)
  controller.trackReachTarget(cta)
  controller.trackReachTarget(cta)

  assert.deepEqual(calls, [
    ["section_reached", "PRICING"],
    ["cta_reached", "bottom_registration"],
  ])
})

test("同一訪問の再接続後も到達イベントをブラウザから再送しない", () => {
  const environment = loadController()
  const firstCalls = []
  const firstController = Object.assign(new environment.Controller(), {
    analyticsEnabled: true,
    trackedOnceEvents: new Set(),
    visitIdValue: "visit-uuid",
    sendAnalytics: (...args) => firstCalls.push(args),
  })
  const section = {
    dataset: {
      lpAnalyticsReachType: "section_reached",
      lpAnalyticsEventValue: "FLOW",
    },
  }

  firstController.trackReachTarget(section)

  const secondCalls = []
  const secondController = Object.assign(new environment.Controller(), {
    analyticsEnabled: true,
    visitIdValue: "visit-uuid",
    sendAnalytics: (...args) => secondCalls.push(args),
  })
  secondController.trackedOnceEvents = secondController.loadTrackedOnceEvents()
  secondController.trackReachTarget(section)

  assert.deepEqual(firstCalls, [["section_reached", "FLOW"]])
  assert.deepEqual(secondCalls, [])
})

test("CTA clickは遷移を止めず実クリック回数分送信する", () => {
  const environment = loadController()
  const calls = []
  let preventDefaultCount = 0
  const controller = Object.assign(new environment.Controller(), {
    sendAnalytics: (...args) => calls.push(args),
  })
  const event = {
    currentTarget: { dataset: { lpAnalyticsClickValue: "bottom_contact" } },
    preventDefault() { preventDefaultCount += 1 },
  }

  controller.trackCtaClick(event)
  controller.trackCtaClick(event)

  assert.deepEqual(calls, [
    ["cta_clicked", "bottom_contact"],
    ["cta_clicked", "bottom_contact"],
  ])
  assert.equal(preventDefaultCount, 0)
})

test("FAQは開いた回数分だけ安定keyを送信する", () => {
  const environment = loadController()
  const calls = []
  const classList = { add() {}, remove() {} }
  const answer = {
    dataset: { open: "false" },
    classList,
    style: {},
    scrollHeight: 100,
    offsetHeight: 0,
    addEventListener() {},
    removeEventListener() {},
  }
  const question = { classList, setAttribute() {} }
  const item = {
    dataset: { lpAnalyticsFaqValue: "faq_2" },
    querySelector(selector) {
      return selector === ".a" ? answer : question
    },
  }
  const controller = Object.assign(new environment.Controller(), {
    element: { querySelectorAll: () => [item] },
    onAnswerTransitionEnd() {},
    sendAnalytics: (...args) => calls.push(args),
  })
  const event = { currentTarget: item }

  controller.toggleQuestion(event)
  controller.toggleQuestion(event)
  controller.toggleQuestion(event)

  assert.deepEqual(calls, [
    ["faq_opened", "faq_2"],
    ["faq_opened", "faq_2"],
  ])
})

test("Turbo previewではlp_viewやobserverを開始しない", () => {
  const environment = loadController({ trackable: false })
  const controller = Object.assign(new environment.Controller(), {
    element: { querySelectorAll: () => [] },
    hasEventsUrlValue: true,
    eventsUrlValue: "/lp_analytics/events",
    hasVisitIdValue: true,
    visitIdValue: "visit-uuid",
    onCtaClick() {},
  })

  controller.startAnalytics()

  assert.equal(controller.analyticsEnabled, false)
  assert.equal(environment.senderInstances.length, 0)
  assert.equal(environment.rememberedVisits.length, 0)
})
