const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")

function setup(respond = () => ({ status: 200, body: { id: 12, state: "complete" } })) {
  const requests = [], cancellations = []
  class XHR extends EventTarget {
    constructor() { super(); this.upload = new EventTarget(); this.headers = {} }
    open(method, url) { Object.assign(this, { method, url }) }
    setRequestHeader(name, value) { this.headers[name] = value }
    send(body) {
      requests.push(this); this.body = body
      const result = respond(this)
      if (!result) return
      queueMicrotask(() => {
        if (this.aborted) return
        if (result.timeout) this.ontimeout?.()
        else if (result.network) this.onerror?.()
        else {
          this.status = result.status
          this.responseText = typeof result.body === "string" ? result.body : JSON.stringify(result.body)
          this.onload?.()
        }
        this.dispatchEvent(new Event("loadend"))
      })
    }
    abort() { this.aborted = true; this.onabort?.(); this.dispatchEvent(new Event("abort")); this.dispatchEvent(new Event("loadend")) }
  }
  let source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers/image_upload_verification/upload_client.js"), "utf8")
  source = source.replaceAll("export function ", "function ").replace("export class UploadVerificationClient", "class UploadVerificationClient")
  source += "\nglobalThis.Client = UploadVerificationClient; globalThis.validate = validateUploadPair"
  const context = vm.createContext({ Blob, File, FormData, XMLHttpRequest: XHR, queueMicrotask, performance,
    navigator: { userAgent: "test-browser" }, document: { querySelector: () => ({ content: "csrf-test" }) },
    fetch: async (url, options) => { cancellations.push({ url, options }); return {} } })
  vm.runInContext(source, context)
  const client = new context.Client({ url: "/runs" })
  return { ...context, client, requests, cancellations }
}

const pair = () => ({ source: new Blob(["source"], { type: "image/jpeg" }), display: new Blob(["display"], { type: "image/jpeg" }), cropData: { schemaVersion: 1 } })

test("validates generated JPEG bytes before creating an upload run", () => {
  const { validate } = setup()
  validate(pair())
  for (const replacement of [{ size: 0, type: "image/jpeg" }, { size: 21 * 1024 ** 2, type: "image/jpeg" }, { size: 1, type: "image/png" }]) {
    assert.throws(() => validate({ ...pair(), source: replacement }), /容量/)
  }
  assert.throws(() => validate({ ...pair(), display: { size: 6 * 1024 ** 2, type: "image/jpeg" } }), /容量/)
})

test("multipart posts the current pair with CSRF and measures the result without original filenames", async () => {
  const { client, requests, cancellations } = setup()
  const result = await client.upload(pair(), "multipart")
  assert.equal(result.state, "complete")
  assert.equal(requests.length, 2)
  assert.equal(requests[1].headers["X-CSRF-Token"], "csrf-test")
  assert.equal(requests[1].headers["Content-Type"], undefined)
  assert.equal(requests[1].body.get("verification[source]").name, "source.jpg")
  assert.equal(requests[1].body.get("verification[display]").name, "display.jpg")
  assert.equal(cancellations.length, 0)
  assert.equal(result.user_agent, "test-browser")
})

test("direct sends two separate owned roles then completes with their signed ids", async () => {
  const { client, requests } = setup()
  const roles = []
  client.directUploadClass = class {
    constructor(file, url) { this.file = file; this.url = url }
    create(callback) { roles.push(this.url); callback(null, { signed_id: this.file.name }) }
  }
  await client.upload(pair(), "direct")
  assert.deepEqual(roles, ["/runs/12/direct_upload/source", "/runs/12/direct_upload/display"])
  assert.equal(requests[1].url, "/runs/12/complete")
  assert.deepEqual(JSON.parse(requests[1].body).verification, { source: "source.jpg", display: "display.jpg" })
})

test("HTTP error, login HTML, network and timeout never report success and schedule cancellation", async () => {
  for (const response of [{ status: 413, body: "too large" }, { status: 200, body: "<html>login</html>" }, { network: true }, { timeout: true }]) {
    const { client, cancellations } = setup(xhr => xhr.url === "/runs" ? { status: 201, body: { id: 12 } } : response)
    await assert.rejects(client.upload(pair(), "multipart"))
    assert.equal(cancellations.length, 1)
    assert.equal(cancellations[0].options.method, "DELETE")
    assert.equal(client.requests.size, 0)
  }
})

test("cancel aborts a pending transfer and prevents a stale success", async () => {
  const { client, requests, cancellations } = setup(xhr => xhr.url === "/runs" ? { status: 201, body: { id: 12 } } : null)
  const task = client.upload(pair(), "multipart")
  await new Promise(setImmediate)
  client.cancel()
  await assert.rejects(task, /中止/)
  assert.equal(requests[1].aborted, true)
  assert.equal(cancellations.length, 1)
})

test("direct failure does not complete a partial pair and permits a fresh client retry", async () => {
  const { client, requests, cancellations } = setup()
  client.directUploadClass = class { create(callback) { callback("simulated") } }
  await assert.rejects(client.upload(pair(), "direct"), /直接送信/)
  assert.equal(requests.length, 1)
  assert.equal(cancellations.length, 1)
  assert.equal((await setup().client.upload(pair(), "multipart")).state, "complete")
})
