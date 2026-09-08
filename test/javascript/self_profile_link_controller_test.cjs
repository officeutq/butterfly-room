const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const source = fs.readFileSync(path.resolve(__dirname,
  "../../app/javascript/controllers/self_profile_link_controller.js"), "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
  .replace("export default class extends Controller", "globalThis.SelfProfileLink = class extends Controller")

function setup(viewerId, authorId = "42") {
  const document = {
    body: { dataset: { currentUserId: viewerId } },
    createElement(tagName) { return { tagName, textContent: "" } }
  }
  const context = vm.createContext({ document })
  vm.runInContext(source, context)
  const controller = new context.SelfProfileLink()
  controller.userIdValue = authorId
  controller.urlValue = `/users/${authorId}`
  let text = "<img src=x onerror=alert(1)>"
  const element = {
    children: [],
    get textContent() { return this.children[0]?.textContent ?? text },
    set textContent(value) { text = value; this.children = [] },
    replaceChildren(child) { this.children = [child] }
  }
  controller.element = element
  return { controller, element, document }
}

test("same shared comment becomes a link only in the authors browser", () => {
  for (const viewer of [undefined, "", "7", "42"] ) {
    const { controller, element } = setup(viewer)
    controller.connect()
    assert.equal(element.children.length, viewer === "42" ? 1 : 0)
    assert.equal(element.textContent, "<img src=x onerror=alert(1)>")
    if (viewer === "42") {
      assert.equal(element.children[0].tagName, "a")
      assert.equal(element.children[0].href, "/users/42")
    }
  }
})

test("cache and disconnect remove the owner link before another session reconnects", () => {
  const { controller, element, document } = setup("42")
  controller.connect()
  controller.reset()
  assert.equal(element.children.length, 0)
  controller.connect()
  controller.disconnect()
  assert.equal(element.children.length, 0)
  document.body.dataset.currentUserId = "7"
  controller.connect()
  assert.equal(element.children.length, 0)
  document.body.dataset.currentUserId = "42"
  controller.connect()
  assert.equal(element.children.length, 1)
})
