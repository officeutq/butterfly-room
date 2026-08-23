const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/store_faq_controller.js"
)

function loadController(hash = "") {
  let source = fs.readFileSync(controllerPath, "utf8")
  source = source.replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}"
  )
  source = source.replace(
    "export default class extends Controller",
    "globalThis.StoreFaqController = class extends Controller"
  )

  const context = vm.createContext({ console, window: { location: { hash } } })
  vm.runInContext(source, context, { filename: controllerPath })
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

function button(key) {
  const attributes = {}
  return {
    dataset: { categoryKey: key },
    classList: classList(),
    setAttribute(name, value) { attributes[name] = value },
    getAttribute(name) { return attributes[name] },
  }
}

function category(key, questionId = null) {
  return {
    dataset: { categoryKey: key },
    hidden: false,
    querySelector(selector) {
      return selector === questionId ? {} : null
    },
  }
}

test("connect selects the first category and hides the remaining categories", () => {
  const Controller = loadController()
  const firstCategory = category("service")
  const secondCategory = category("sales")
  const firstButton = button("service")
  const secondButton = button("sales")
  const controller = Object.assign(new Controller(), {
    categoryTargets: [firstCategory, secondCategory],
    categoryButtonTargets: [firstButton, secondButton],
  })

  controller.connect()

  assert.equal(firstCategory.hidden, false)
  assert.equal(secondCategory.hidden, true)
  assert.equal(firstButton.getAttribute("aria-pressed"), "true")
  assert.equal(secondButton.getAttribute("aria-pressed"), "false")
  assert.equal(firstButton.classList.contains("is-active"), true)
})

test("category button switches the visible category and selected state", () => {
  const Controller = loadController()
  const firstCategory = category("service")
  const secondCategory = category("sales")
  const firstButton = button("service")
  const secondButton = button("sales")
  const controller = Object.assign(new Controller(), {
    categoryTargets: [firstCategory, secondCategory],
    categoryButtonTargets: [firstButton, secondButton],
  })

  controller.selectCategory({ currentTarget: secondButton })

  assert.equal(firstCategory.hidden, true)
  assert.equal(secondCategory.hidden, false)
  assert.equal(firstButton.getAttribute("aria-pressed"), "false")
  assert.equal(secondButton.getAttribute("aria-pressed"), "true")
})

test("question hash selects the category containing that question", () => {
  const Controller = loadController("#faq-q15")
  const firstCategory = category("service")
  const secondCategory = category("getting-started", "#faq-q15")
  const controller = Object.assign(new Controller(), {
    categoryTargets: [firstCategory, secondCategory],
    categoryButtonTargets: [button("service"), button("getting-started")],
  })

  controller.connect()

  assert.equal(firstCategory.hidden, true)
  assert.equal(secondCategory.hidden, false)
})
