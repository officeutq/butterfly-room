const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers/share_controller.js"), "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
  .replace("export default class extends Controller", "globalThis.Share = class extends Controller")

function setup({ navigator = {}, dataset = {} } = {}) {
  const timers = []
  const flashes = []
  const context = vm.createContext({ navigator, document: { title: "ページタイトル" },
    window: { setTimeout: (callback, delay) => timers.push({ callback, delay }) } })
  vm.runInContext(source, context)
  const controller = new context.Share()
  controller.element = { disabled: false, dataset: {
    shareTitle: "Butterflyve", shareText: "Butterflyveの店舗管理者招待はこちら",
    shareUrl: "https://example.test/store_admin_invitations/test-token", ...dataset
  } }
  controller.showFlash = (level, message) => flashes.push({ level, message })
  return { controller, flashes, timers }
}

const click = () => ({ preventDefault() {} })

test("店舗管理者招待は本文に案内文と正しいURLを1回含め、別のURL欄には渡さない", async () => {
  let payload
  const { controller, timers } = setup({
    navigator: { share: async value => { payload = value } }, dataset: { shareUrlInText: "true" }
  })
  await controller.share(click())
  const { shareText, shareUrl } = controller.element.dataset
  assert.equal(payload.title, "Butterflyve")
  assert.equal(payload.text, `${shareText}\n\n${shareUrl}`)
  assert.equal(payload.text.split(shareUrl).length - 1, 1)
  assert.equal(Object.hasOwn(payload, "url"), false)
  assert.equal(controller.element.disabled, true)
  assert.equal(timers[0].delay, 300)
  timers[0].callback()
  assert.equal(controller.element.disabled, false)
})

test("指定のないブース共有と明示的に無効にした配信共有は本文とURLを別々に渡す", async () => {
  for (const dataset of [
    { shareText: "キャストのブースはこちら🦋", shareUrl: "https://example.test/booths/1/share" },
    { shareText: "配信はここから！遊びに来てね🦋", shareUrl: "https://example.test/booths/1/share?stream=2", shareUrlInText: "false" }
  ]) {
    let payload
    const { controller } = setup({ navigator: { share: async value => { payload = value } }, dataset })
    await controller.share(click())
    assert.equal(payload.title, "Butterflyve")
    assert.equal(payload.text, dataset.shareText)
    assert.equal(payload.url, dataset.shareUrl)
  }
})

test("本文へURLを含める場合も案内文が空ならURLだけを渡す", async () => {
  let payload
  const { controller } = setup({
    navigator: { share: async value => { payload = value } }, dataset: { shareUrlInText: "true", shareText: "" }
  })
  await controller.share(click())
  assert.equal(payload.text, controller.element.dataset.shareUrl)
  assert.equal(Object.hasOwn(payload, "url"), false)
})

test("共有の取消はエラーを表示せず再操作できる", async () => {
  const { controller, flashes, timers } = setup({ navigator: {
    share: async () => { throw Object.assign(new Error("cancelled"), { name: "AbortError" }) }
  }, dataset: { shareUrlInText: "true" } })
  await controller.share(click())
  assert.deepEqual(flashes, [])
  timers[0].callback()
  assert.equal(controller.element.disabled, false)
})

test("共有失敗後も再操作で同じ招待URLを共有できる", async () => {
  let calls = 0
  let payload
  const { controller, flashes, timers } = setup({ navigator: { share: async value => {
    if (++calls === 1) throw new Error("failed")
    payload = value
  } }, dataset: { shareUrlInText: "true" } })
  await controller.share(click())
  assert.deepEqual(flashes, [{ level: "danger", message: "共有に失敗しました" }])
  timers[0].callback()
  assert.equal(controller.element.disabled, false)
  await controller.share(click())
  assert.equal(calls, 2)
  assert.equal(payload.text, `${controller.element.dataset.shareText}\n\n${controller.element.dataset.shareUrl}`)
  timers[1].callback()
  assert.equal(controller.element.disabled, false)
})

test("共有非対応ならコピーの案内を表示しボタンを無効にしない", async () => {
  const { controller, flashes, timers } = setup({ dataset: { shareUrlInText: "true" } })
  await controller.share(click())
  assert.deepEqual(flashes, [{ level: "warning", message: "このブラウザでは共有機能を利用できません。コピーをご利用ください。" }])
  assert.equal(controller.element.disabled, false)
  assert.equal(timers.length, 0)
})

test("URLがなければ案内文だけで共有しない", async () => {
  let calls = 0
  const { controller } = setup({ navigator: { share: async () => { calls++ } },
    dataset: { shareUrlInText: "true", shareUrl: "" } })
  await controller.share(click())
  assert.equal(calls, 0)
  assert.equal(controller.element.disabled, false)
})
