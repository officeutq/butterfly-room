const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const senderPath = path.resolve(
  __dirname,
  "../../app/javascript/lp_analytics/event_sender.js"
)

function loadSenderModule() {
  let source = fs.readFileSync(senderPath, "utf8")
  source = source.replaceAll("export function ", "function ")
  source = source.replace("export class EventSender", "class EventSender")
  source += `
    globalThis.LpAnalyticsSender = {
      EventSender,
      isTrackableDocument,
      viewportType,
      rememberVisitId,
      storedVisitId,
    }
  `

  const context = vm.createContext({ console, Promise, Uint8Array })
  vm.runInContext(source, context, { filename: senderPath })
  return context.LpAnalyticsSender
}

function buildDocument({ preview = false, prerendering = false, visibilityState = "visible" } = {}) {
  return {
    prerendering,
    visibilityState,
    documentElement: {
      clientWidth: 0,
      hasAttribute(name) {
        return preview && name === "data-turbo-preview"
      },
    },
    querySelector(selector) {
      return selector === 'meta[name="csrf-token"]' ? { content: "csrf-token" } : null
    },
  }
}

test("Turbo previewとprerenderを実表示として扱わない", () => {
  const { isTrackableDocument } = loadSenderModule()

  assert.equal(isTrackableDocument(buildDocument()), true)
  assert.equal(isTrackableDocument(buildDocument({ preview: true })), false)
  assert.equal(isTrackableDocument(buildDocument({ prerendering: true })), false)
  assert.equal(isTrackableDocument(buildDocument({ visibilityState: "prerender" })), false)
})

test("viewportをPC・tablet・smartphoneへ正規化する", () => {
  const { viewportType } = loadSenderModule()
  const documentReference = buildDocument()

  assert.equal(viewportType({ innerWidth: 375 }, documentReference), "smartphone")
  assert.equal(viewportType({ innerWidth: 800 }, documentReference), "tablet")
  assert.equal(viewportType({ innerWidth: 1440 }, documentReference), "pc")
})

test("匿名訪問IDを同一tabのsessionStorageへ保持する", () => {
  const { rememberVisitId, storedVisitId } = loadSenderModule()
  const values = new Map()
  const storage = {
    setItem(key, value) { values.set(key, value) },
    getItem(key) { return values.get(key) || null },
  }

  rememberVisitId("visit-uuid", storage)

  assert.equal(storedVisitId(storage), "visit-uuid")
})

test("許可された匿名情報だけをCSRF付きkeepalive requestで送信する", async () => {
  const { EventSender } = loadSenderModule()
  const requests = []
  const windowReference = {
    crypto: { randomUUID: () => "123e4567-e89b-42d3-a456-426614174000" },
    fetch(url, options) {
      requests.push({ url, options })
      return Promise.resolve({ ok: true })
    },
  }
  const sender = new EventSender({
    eventsUrl: "/lp_analytics/events",
    visitId: "123e4567-e89b-42d3-a456-426614174001",
    windowReference,
    documentReference: buildDocument(),
  })

  assert.equal(
    await sender.send("cta_clicked", "hero_registration", { viewport_type: "smartphone" }),
    true
  )
  assert.equal(requests.length, 1)
  assert.equal(requests[0].url, "/lp_analytics/events")
  assert.equal(requests[0].options.keepalive, true)
  assert.equal(requests[0].options.credentials, "same-origin")
  assert.equal(requests[0].options.headers["X-CSRF-Token"], "csrf-token")
  assert.deepEqual(JSON.parse(requests[0].options.body), {
    lp_analytics_event: {
      visit_id: "123e4567-e89b-42d3-a456-426614174001",
      event_id: "123e4567-e89b-42d3-a456-426614174000",
      event_type: "cta_clicked",
      event_value: "hero_registration",
      metadata: { viewport_type: "smartphone" },
    },
  })
  assert.doesNotMatch(
    requests[0].options.body,
    /email|phone_number|password|location|cookie|referrer/
  )
})

test("送信失敗を画面操作へ伝播させない", async () => {
  const { EventSender } = loadSenderModule()
  const sender = new EventSender({
    eventsUrl: "/lp_analytics/events",
    windowReference: {
      crypto: { randomUUID: () => "123e4567-e89b-42d3-a456-426614174000" },
      fetch() { return Promise.reject(new Error("network error")) },
    },
    documentReference: buildDocument(),
  })

  assert.equal(await sender.send("lp_view"), false)
})

test("randomUUIDがない場合もversion 4 UUIDを生成する", () => {
  const { EventSender } = loadSenderModule()
  const sender = new EventSender({
    eventsUrl: "/lp_analytics/events",
    windowReference: {
      crypto: {
        getRandomValues(bytes) {
          bytes.fill(0xab)
          return bytes
        },
      },
    },
    documentReference: buildDocument(),
  })

  assert.match(
    sender.generateUuid(),
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  )
})
