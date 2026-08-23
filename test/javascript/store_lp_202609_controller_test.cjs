const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/store_lp_202609_controller.js"
)

function loadController({ reducedMotion = false, hasIntersectionObserver = true } = {}) {
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source.replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}"
  )
  source = source.replace(
    "export default class extends Controller",
    "globalThis.StoreLp202609Controller = class extends Controller"
  )

  const window = {
    scrollY: 0,
    addEventListener() {},
    removeEventListener() {},
    matchMedia: () => ({ matches: reducedMotion }),
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

  const context = vm.createContext({ console, window })
  vm.runInContext(source, context, { filename: controllerPath })

  return { Controller: context.StoreLp202609Controller, window }
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
