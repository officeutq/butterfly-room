const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/store_lp_202609_controller.js"
)

function loadController({ reducedMotion = false, hasIntersectionObserver = true, trackable = true } = {}) {
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
    "globalThis.StoreLp202609Controller = class extends Controller"
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
    scrollY: 0,
    innerHeight: 1000,
    addEventListener() {},
    removeEventListener() {},
    matchMedia: () => ({ matches: reducedMotion }),
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

  if (hasIntersectionObserver) {
    window.IntersectionObserver = class {
      constructor(callback, options) {
        this.callback = callback
        this.options = options
        this.observed = []
        this.unobserved = []
      }

      observe(target) { this.observed.push(target) }
      unobserve(target) { this.unobserved.push(target) }
      disconnect() {}
    }
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
    Controller: context.StoreLp202609Controller,
    document,
    window,
    rememberedVisits,
    senderInstances,
  }
}

function classList() {
  const values = new Set()
  return {
    add(value) { values.add(value) },
    toggle(value, force) {
      if (force) values.add(value)
      else values.delete(value)
    },
    contains(value) { return values.has(value) },
  }
}

test("scroll position toggles the compact header state", () => {
  const environment = loadController()
  const headerClassList = classList()
  const controller = Object.assign(new environment.Controller(), {
    hasHeaderTarget: true,
    headerTarget: { classList: headerClassList },
  })

  controller.updateHeader()
  assert.equal(headerClassList.contains("is-scrolled"), false)

  environment.window.scrollY = 25
  controller.updateHeader()
  assert.equal(headerClassList.contains("is-scrolled"), true)
})

test("reduced motion displays every reveal target without an observer", () => {
  const environment = loadController({ reducedMotion: true })
  const firstClassList = classList()
  const secondClassList = classList()
  const controller = Object.assign(new environment.Controller(), {
    revealTargets: [
      { classList: firstClassList },
      { classList: secondClassList },
    ],
  })

  controller.observeRevealTargets()

  assert.equal(firstClassList.contains("is-visible"), true)
  assert.equal(secondClassList.contains("is-visible"), true)
  assert.equal(controller.revealObserver, undefined)
})

test("intersection observer reveals visible targets", () => {
  const environment = loadController()
  const targetClassList = classList()
  const target = { classList: targetClassList }
  const controller = Object.assign(new environment.Controller(), {
    revealTargets: [target],
  })

  controller.observeRevealTargets()
  assert.deepEqual(controller.revealObserver.observed, [target])

  controller.revealObserver.callback([{ target, isIntersecting: true }])

  assert.equal(targetClassList.contains("is-visible"), true)
  assert.deepEqual(controller.revealObserver.unobserved, [target])
})

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

test("sectionとCTA位置到達は重複せずCTA clickは実回数分送信する", () => {
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
      lpAnalyticsEventValue: "adoption_cost",
    },
  }
  const cta = {
    dataset: {
      lpAnalyticsReachType: "cta_reached",
      lpAnalyticsEventValue: "bottom_registration",
      lpAnalyticsClickValue: "bottom_registration",
    },
  }

  controller.trackReachTarget(section)
  controller.trackReachTarget(section)
  controller.trackReachTarget(cta)
  controller.trackReachTarget(cta)
  controller.trackCtaClick({ currentTarget: cta })
  controller.trackCtaClick({ currentTarget: cta })

  assert.deepEqual(calls, [
    ["section_reached", "adoption_cost"],
    ["cta_reached", "bottom_registration"],
    ["cta_clicked", "bottom_registration"],
    ["cta_clicked", "bottom_registration"],
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
