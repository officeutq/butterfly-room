const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/store_faq_controller.js"
)

function loadController({ hash = "", reducedMotion = false, document = {} } = {}) {
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source.replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}"
  )
  source = source.replace(
    "export default class extends Controller",
    "globalThis.StoreFaqController = class extends Controller"
  )

  const window = {
    location: { hash },
    matchMedia: () => ({ matches: reducedMotion }),
    scrollCalls: [],
    scrollTo(options) { this.scrollCalls.push(options) },
  }
  const context = vm.createContext({ console, document, window })
  vm.runInContext(source, context, { filename: controllerPath })
  context.StoreFaqController.testWindow = window
  return context.StoreFaqController
}

function classList() {
  const values = new Set()
  return {
    toggle(value, force) {
      if (force) values.add(value)
      else values.delete(value)
    },
    contains(value) { return values.has(value) },
  }
}

function categoryLink(key, categoryId) {
  const attributes = { "aria-controls": categoryId }
  return {
    dataset: { categoryKey: key },
    classList: classList(),
    setAttribute(name, value) { attributes[name] = value },
    getAttribute(name) { return attributes[name] },
    removeAttribute(name) { delete attributes[name] },
  }
}

function category(key, { id = `store-faq-category-${key}`, questionId = null } = {}) {
  return {
    id,
    dataset: { categoryKey: key },
    hidden: false,
    scrollCalls: [],
    querySelector(selector) {
      return selector === questionId ? {} : null
    },
    scrollIntoView(options) { this.scrollCalls.push(options) },
  }
}

function eventFor(currentTarget) {
  return {
    currentTarget,
    defaultPrevented: false,
    preventDefault() { this.defaultPrevented = true },
  }
}

test("connect keeps every category visible and marks the first table-of-contents link", () => {
  const Controller = loadController()
  const firstCategory = category("service")
  const secondCategory = category("sales")
  const firstLink = categoryLink("service", firstCategory.id)
  const secondLink = categoryLink("sales", secondCategory.id)
  const controller = Object.assign(new Controller(), {
    categoryTargets: [firstCategory, secondCategory],
    categoryLinkTargets: [firstLink, secondLink],
  })

  controller.connect()

  assert.equal(firstCategory.hidden, false)
  assert.equal(secondCategory.hidden, false)
  assert.equal(firstLink.getAttribute("aria-current"), "page")
  assert.equal(secondLink.getAttribute("aria-current"), undefined)
  assert.equal(firstLink.classList.contains("is-active"), true)
})

test("table-of-contents link smoothly scrolls to its category", () => {
  const firstCategory = category("service")
  const secondCategory = category("sales")
  const firstLink = categoryLink("service", firstCategory.id)
  const secondLink = categoryLink("sales", secondCategory.id)
  const document = {
    getElementById(id) {
      return [firstCategory, secondCategory].find((item) => item.id === id)
    },
  }
  const Controller = loadController({ document })
  const controller = Object.assign(new Controller(), {
    categoryTargets: [firstCategory, secondCategory],
    categoryLinkTargets: [firstLink, secondLink],
  })
  const event = eventFor(secondLink)

  controller.scrollToCategory(event)

  assert.equal(event.defaultPrevented, true)
  assert.equal(secondCategory.scrollCalls.length, 1)
  assert.equal(secondCategory.scrollCalls[0].behavior, "smooth")
  assert.equal(secondCategory.scrollCalls[0].block, "start")
  assert.equal(firstLink.getAttribute("aria-current"), undefined)
  assert.equal(secondLink.getAttribute("aria-current"), "page")
})

test("page-top link smoothly scrolls to the FAQ top", () => {
  const Controller = loadController()
  const firstCategory = category("service")
  const secondCategory = category("sales")
  const firstLink = categoryLink("service", firstCategory.id)
  const secondLink = categoryLink("sales", secondCategory.id)
  const controller = Object.assign(new Controller(), {
    categoryTargets: [firstCategory, secondCategory],
    categoryLinkTargets: [firstLink, secondLink],
  })
  const event = eventFor({})

  controller.scrollToTop(event)

  assert.equal(event.defaultPrevented, true)
  assert.equal(Controller.testWindow.scrollCalls.length, 1)
  assert.equal(Controller.testWindow.scrollCalls[0].top, 0)
  assert.equal(Controller.testWindow.scrollCalls[0].behavior, "smooth")
  assert.equal(firstLink.getAttribute("aria-current"), "page")
  assert.equal(secondLink.getAttribute("aria-current"), undefined)
})

test("question card animates open and closed", () => {
  const Controller = loadController()
  const summary = { offsetHeight: 70 }
  const style = {
    height: "",
    overflow: "",
    removeProperty(name) { this[name] = "" },
  }
  const animations = []
  const details = {
    open: false,
    dataset: {},
    style,
    get offsetHeight() { return this.open ? 240 : 70 },
    querySelector(selector) { return selector === "summary" ? summary : null },
    animate(keyframes, options) {
      const animation = { keyframes, options, cancel() {} }
      animations.push(animation)
      return animation
    },
  }
  const currentTarget = { closest: () => details }
  const controller = new Controller()

  controller.toggleQuestion(eventFor(currentTarget))

  assert.equal(details.open, true)
  assert.equal(animations[0].keyframes.height[0], "70px")
  assert.equal(animations[0].keyframes.height[1], "240px")
  assert.equal(animations[0].options.duration, 260)
  animations[0].onfinish()
  assert.equal(details.style.height, "")

  controller.toggleQuestion(eventFor(currentTarget))

  assert.equal(animations[1].keyframes.height[0], "240px")
  assert.equal(animations[1].keyframes.height[1], "70px")
  animations[1].onfinish()
  assert.equal(details.open, false)
  assert.equal(details.dataset.animating, undefined)
})

test("question hash selects the table-of-contents link for its category", () => {
  const Controller = loadController({ hash: "#faq-q15" })
  const firstCategory = category("service")
  const secondCategory = category("getting-started", { questionId: "#faq-q15" })
  const firstLink = categoryLink("service", firstCategory.id)
  const secondLink = categoryLink("getting-started", secondCategory.id)
  const controller = Object.assign(new Controller(), {
    categoryTargets: [firstCategory, secondCategory],
    categoryLinkTargets: [firstLink, secondLink],
  })

  controller.connect()

  assert.equal(firstLink.getAttribute("aria-current"), undefined)
  assert.equal(secondLink.getAttribute("aria-current"), "page")
})
