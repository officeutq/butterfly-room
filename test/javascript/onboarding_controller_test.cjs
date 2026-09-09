const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const test = require("node:test")

function setup() {
  const events = new Map()
  const source = fs.readFileSync("app/javascript/controllers/onboarding_controller.js", "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace('import * as bootstrap from "bootstrap"', "const bootstrap = {}")
    .replace("export default class extends Controller", "globalThis.Onboarding = class extends Controller")
  const document = { querySelector: () => null, addEventListener() {}, removeEventListener() {} }
  const context = vm.createContext({ document, requestAnimationFrame: () => {}, window: {
    addEventListener: (name, listener) => events.set(name, listener), removeEventListener() {}, clearTimeout() {}
  } })
  vm.runInContext(source, context)
  const c = new context.Onboarding()
  c.connect()
  return { c, events, document }
}

test("initial and legacy invitation steps point to footer", () => {
  const { c } = setup()
  for (const step of ["invite_cast", "create_invite"]) {
    c.stepValue = step
    assert.equal(c.stepConfig().target, "footer-cast-invite")
  }
})

test("modal suspends background tutorial until actual close", () => {
  const { c, events } = setup()
  let renderTargets = 0
  c.stepConfig = () => { renderTargets++; return null }
  events.get("app-modal:opening")()
  c.update({ detail: { step: "go_dashboard_for_drinks", storeId: 8 } })
  assert.equal(renderTargets, 0)
  assert.equal(c.storeIdValue, 8)
  events.get("app-modal:closed")()
  assert.equal(renderTargets, 1)
})

test("shared progress points to dashboard without issuing again", () => {
  const { c } = setup()
  c.stepValue = "go_dashboard_for_drinks"
  assert.equal(c.stepConfig().target, "footer-dashboard")
})

test("completed skipped and unset stores have no tutorial", () => {
  const { c } = setup()
  for (const step of ["completed", "skipped", "", undefined]) {
    c.stepValue = step
    assert.equal(c.stepConfig(), null)
  }
})

test("reconnecting clears stale modal suspension", () => {
  const { c, events } = setup()
  events.get("app-modal:opening")()
  c.disconnect()
  c.connect()
  assert.equal(c.modalOpen, false)
})

test("invitation modal guides sharing then closing and never highlights the background", () => {
  const { c, events, document } = setup()
  const modal = { dataset: { onboardingInvitationState: "share" }, querySelector: () => ({}) }
  document.querySelector = () => modal
  const messages = []
  c.applyHighlight = () => {}
  c.showPopover = (_target, message) => messages.push(message)
  c.stepValue = "create_invite"
  events.get("app-modal:opening")()
  events.get("app-modal:shown")()
  assert.match(messages.at(-1), /招待URLを共有・コピー/)
  assert.equal(c.modalStepConfig(modal).target, "invitation-share")
  modal.dataset.onboardingInvitationState = "close"
  c.update({ detail: { step: "go_dashboard_for_drinks", storeId: 8 } })
  assert.equal(c.modalStepConfig(modal).target, "invitation-close")
  assert.equal(messages.at(-1), "共有操作が完了したら、『閉じる』を押して、次の設定に進みましょう。")
  modal.dataset.onboardingInvitationMode = "copy"
  assert.match(c.modalStepConfig(modal).message, /貼り付けて送ったら/)
  c.stepValue = "skipped"
  assert.equal(c.modalStepConfig(modal), null)
  c.stepValue = "create_invite"
  assert.equal(c.modalStepConfig({ dataset: {} }), null)
})
