const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")

function setup(response = { status: 200, body: { state: "complete" } }) {
  const requests = []
  class XHR {
    constructor() { this.headers = {} }
    open(method, url) { Object.assign(this, { method, url }) }
    setRequestHeader(name, value) { this.headers[name] = value }
    getResponseHeader(name) {
      if (name !== "Content-Type") return null
      return response.contentType || (typeof response.body === "string" ? "text/html" : "application/json")
    }
    send(body) {
      this.body = body
      requests.push(this)
      if (!response) return

      queueMicrotask(() => {
        if (response.type === "timeout") this.ontimeout?.()
        else if (response.type === "network") this.onerror?.()
        else {
          this.status = response.status
          this.responseText = typeof response.body === "string" ? response.body : JSON.stringify(response.body)
          this.onload?.()
        }
        this.onloadend?.()
      })
    }
    abort() {
      this.onabort?.()
      this.onloadend?.()
    }
  }

  let source = fs.readFileSync(
    path.resolve(__dirname, "../../app/javascript/image_attachments/multipart_client.js"),
    "utf8"
  )
  source = source
    .replace("export const IMAGE_PAIR_MULTIPART_TIMEOUT_MS", "const IMAGE_PAIR_MULTIPART_TIMEOUT_MS")
    .replace("export class ImagePairMultipartError", "class ImagePairMultipartError")
    .replace("export class ImagePairMultipartClient", "class ImagePairMultipartClient")
  source += "\nglobalThis.Client = ImagePairMultipartClient"
  const context = vm.createContext({
    XMLHttpRequest: XHR,
    FormData,
    document: { querySelector: () => ({ content: "csrf-test" }) },
    queueMicrotask,
  })
  vm.runInContext(source, context)
  return { client: new context.Client(), requests }
}

test("uses the fixed 45 second timeout and sends FormData without overriding its boundary", async () => {
  const { client, requests } = setup()
  const body = new FormData()
  body.append("image_pair[operation]", "delete")

  const result = await client.submit({ url: "/profile", body })

  assert.equal(result.state, "complete")
  assert.equal(requests[0].timeout, 45_000)
  assert.equal(requests[0].headers["X-CSRF-Token"], "csrf-test")
  assert.equal(requests[0].headers["Content-Type"], undefined)
})

test("reports timeout and network interruption as manually retryable", async () => {
  for (const type of ["timeout", "network"]) {
    const { client } = setup({ type })
    const error = await client.submit({ url: "/profile", body: new FormData() }).catch(value => value)

    assert.equal(error.retryable, true)
    assert.match(error.message, /再度保存/)
    assert.equal(client.request, null)
  }
})

test("preserves the server error contract for limits and stale edits", async () => {
  const tooLarge = setup({
    status: 413,
    body: { error: "image_pair_request_too_large", message: "too large", retryable: true },
  })
  const stale = setup({ status: 409, body: {} })

  const limitError = await tooLarge.client.submit({ url: "/profile", body: new FormData() }).catch(value => value)
  const staleError = await stale.client.submit({ url: "/profile", body: new FormData() }).catch(value => value)

  assert.equal(limitError.code, "image_pair_request_too_large")
  assert.equal(limitError.status, 413)
  assert.equal(staleError.retryable, false)
  assert.match(staleError.message, /読み直して/)
})

test("does not treat a login HTML response or a synchronous send failure as success", async () => {
  const login = setup({ status: 200, body: "<html>login</html>" })
  const loginError = await login.client.submit({ url: "/profile", body: new FormData() }).catch(value => value)

  assert.equal(loginError.code, "unexpected_response")

  const broken = setup()
  broken.client.xhrClass.prototype.send = () => { throw new Error("simulated") }
  const sendError = await broken.client.submit({ url: "/profile", body: new FormData() }).catch(value => value)

  assert.equal(sendError.code, "network_error")
  assert.equal(sendError.retryable, true)
  assert.equal(broken.client.request, null)
})

test("does not start overlapping requests and allows an explicit abort", async () => {
  const { client } = setup(null)
  const first = client.submit({ url: "/profile", body: new FormData() })
  const overlapRequest = client.submit({ url: "/profile", body: new FormData() })

  client.abort()
  const overlap = await overlapRequest.catch(value => value)
  assert.match(overlap.message, /送信中/)
  const aborted = await first.catch(value => value)
  assert.equal(aborted.code, "upload_aborted")
})
