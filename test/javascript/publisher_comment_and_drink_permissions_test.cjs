const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function loadController(file, className, document) {
  const source = fs.readFileSync(path.resolve(__dirname, `../../app/javascript/controllers/${file}.js`), "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace('import * as bootstrap from "bootstrap"', "const bootstrap = {}")
    .replace("export default class extends Controller", `globalThis.${className} = class extends Controller`)
  const context = vm.createContext({ document })
  vm.runInContext(source, context)
  return new context[className]()
}

test("同じ配信HTMLから本人だけに消化操作を出しNULL同士を本人としない", () => {
  for (const [viewerId, publisherId, allowed] of [["Y", "Y", true], ["X", "Y", false], ["Z", "Y", false], ["admin", "Y", false], ["", "", false], [undefined, "Y", false]]) {
    const document = { body: { dataset: { currentUserId: viewerId } } }
    const controller = loadController("drink_consume_controller", "DrinkConsume", document)
    controller.publisherIdValue = publisherId
    controller.operationTarget = { hidden: false }
    controller.displayTarget = { hidden: true }
    controller.connect()
    assert.equal(controller.operationTarget.hidden, !allowed)
    assert.equal(controller.displayTarget.hidden, allowed)
    controller.reset()
    assert.equal(controller.operationTarget.hidden, true)
    document.body.dataset.currentUserId = "another"
    controller.connect()
    assert.equal(controller.operationTarget.hidden, true)
    controller.disconnect()
    assert.equal(controller.displayTarget.hidden, false)
  }
})

test("共有コメントの非表示と解除は配信画面の種類に依存せずYのポップアップだけに残す", () => {
  for (const [viewerId, publisherId, expected] of [["Y", "Y", "moderator,report"], ["X", "Y", "report"], ["admin", "Y", "report"], ["", "", "report"], [undefined, "Y", "report"]]) {
    const document = {
      body: { dataset: { currentUserId: viewerId } },
      createElement() {
        return { innerHTML: "", querySelectorAll(selector) {
          assert.equal(selector, "[data-comment-moderator-action]")
          return [{ remove: () => { this.innerHTML = "report" } }]
        } }
      }
    }
    const controller = loadController("comment_actions_controller", "CommentActions", document)
    controller.publisherControlValue = true
    controller.publisherIdValue = publisherId
    controller.contentTarget = { innerHTML: "moderator,report" }
    assert.equal(controller.popoverContent(), expected)
    assert.equal(controller.contentTarget.innerHTML, "moderator,report")
    controller.publisherControlValue = false
    assert.equal(controller.popoverContent(), "moderator,report")
  }
})
